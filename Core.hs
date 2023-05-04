module Core where

stackCapacity :: Int
stackCapacity = 1024 

executionLimit :: Int
executionLimit = 10 ^ 2

data MachineState = MachineState { io :: IO ()
                                 , stack :: [Int]
                                 , ip :: Int
                                 , program :: [Inst]
                                 , labels :: [(String, Int)]
                                 , halted :: Bool
                                 , instsExecuted :: Int
                                 }

data MachineError = StackUnderflow
                  | StackOverflow
                  | DivByZeroError
                  | IllegalInstAccess
                  | LabelNotFoundError
                  deriving Show

newtype Action a = Action { runAction :: MachineState -> Either MachineError (MachineState, a) }

instance Monad Action where
    return = pure
    (Action a) >>= g = Action $ \s -> a s >>= \(s', x) -> runAction (g x) s'

instance Applicative Action where
    pure x = Action $ \s -> Right (s, x)
    a1 <*> a2 = a1 >>= \f -> a2 >>= pure . f

instance Functor Action where
    fmap f a = a >>= pure . f

get :: Action MachineState
get = Action $ \s -> Right (s, s)

put :: MachineState -> Action ()
put x = Action $ \_ -> Right (x, ())

die :: MachineError -> Action ()
die err = Action $ \_ -> Left err

fetch :: Action Inst
fetch = get >>= \s -> let x = ip s
                          y = instsExecuted s
                      in if x < 0 || x >= length (program s) then
                             die IllegalInstAccess >> pure InstHlt
                         else
                             put (s { instsExecuted = y + 1 }) >> pure (program s !! x)

next :: Action ()
next = get >>= \s -> put $ s { ip = ip s + 1 }

jmp :: Int -> Action ()
jmp x = get >>= \s -> put $ s { ip = x }

hlt :: Action ()
hlt = get >>= \s -> put $ s { halted = True }

push :: Int -> Action ()
push x = getStack >>= push'
    where push' s
              | length s == stackCapacity = die StackOverflow
              | otherwise = putStack $ s ++ [x]

pop :: Action Int
pop = getStack >>= pop'
    where pop' s
              | null s = die StackUnderflow >> pure 0
              | otherwise = putStack (init s) >> pure (last s)

getStack :: Action [Int]
getStack = get >>= pure . stack

putStack :: [Int] -> Action ()
putStack x = get >>= \s -> put $ s { stack = x }

getIO :: Action (IO ())
getIO = get >>= pure . io

putIO :: (IO ()) -> Action ()
putIO x = get >>= \s -> put $ s { io = x }

data Inst = InstPush Int
          | InstPop
          | InstPrint
          | InstAdd
          | InstSub
          | InstMul
          | InstDiv
          | InstMod
          | InstJmp String
          | InstHlt
          | InstDup
          deriving Show

exec :: Inst -> Action ()
exec (InstPush x) = push x >> next
exec InstPop = pop >> next
exec InstPrint = do
    state <- get
    let oldio = io state

    elem <- pop
    let newio = print elem
    
    putIO (oldio >> newio)
    next
exec InstAdd = do
    y <- pop
    x <- pop
    push $ x + y
    next
exec InstSub = do
    y <- pop
    x <- pop
    push $ x - y
    next
exec InstMul = do
    y <- pop
    x <- pop
    push $ x * y
    next
exec InstDiv = do
    y <- pop
    if y == 0 then die DivByZeroError else pure ()
    x <- pop
    push $ x `div` y
    next
exec InstMod = do
    y <- pop
    if y == 0 then die DivByZeroError else pure ()
    x <- pop
    push $ x `mod` y
    next
exec (InstJmp l) = get >>= \s -> case lookup l $ labels s of
                                     Just addr -> jmp addr
                                     Nothing -> die LabelNotFoundError
exec InstHlt = hlt
exec InstDup = pop >>= \x -> push x >> push x >> next

initial :: [Inst] -> [(String, Int)] -> MachineState
initial program labels = MachineState { io = pure ()
                                      , stack = []
                                      , ip = 0
                                      , program = program
                                      , labels = labels
                                      , halted = False
                                      , instsExecuted = 0
                                      }

execProg :: [Inst] -> [(String, Int)] -> Either MachineError (IO ())
execProg prog labels = runAction act (initial prog labels) >>= pure . snd
    where act = do
              fetch >>= exec
              s <- get
              if halted s || instsExecuted s > executionLimit then
                  getIO
              else
                  act
