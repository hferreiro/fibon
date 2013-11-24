{-# LANGUAGE BangPatterns #-}
module Fibon.Run.Actions (
      runBundle
    , buildBundle
    , sanityCheckBundle
    , prepNofibBundle
    , FibonError
    , Action(..)
    , ActionRunner
)
where

import Data.List
import Data.Maybe
import Data.Time.Clock.POSIX
import Fibon.BenchmarkInstance
import Fibon.Result
import Fibon.Run.BenchmarkBundle
import Fibon.Run.BenchmarkRunner as Runner
import qualified Fibon.Run.Log as Log
import qualified Fibon.Run.SysTools as SysTools
import Control.Monad.Error
import Control.Monad.Reader
import qualified Control.Exception as C
import Control.Concurrent(forkIO, newEmptyMVar, putMVar, takeMVar)
import System.Directory
import System.FilePath
import System.Process
import System.IO (hClose, hGetContents)

type FibonRunMonad = ErrorT FibonError (ReaderT BenchmarkBundle IO)

data Action =
    Sanity
  | Build
  | Run
  deriving (Read, Show, Eq, Ord, Enum)

type ActionRunner a = (BenchmarkBundle -> IO (Either FibonError a))

data ActionResult =
    SanityComplete
  | BuildComplete BuildData
  | RunComplete   RunData
  deriving(Show)

data FibonError =
    BuildError   String
  | SanityError  String
  | RunError     String
  | OtherError   String -- ^ For general IO exceptions
  deriving (Show)
instance Error FibonError where
  strMsg = OtherError

sanityCheckBundle :: BenchmarkBundle -> IO (Either FibonError ())
sanityCheckBundle bb = runFibonMonad bb $ do
  SanityComplete <- runAction Sanity
  return ()

buildBundle :: BenchmarkBundle -> IO (Either FibonError BuildData)
buildBundle bb = runFibonMonad bb $ do
  BuildComplete br <- runAction Build
  return br

runBundle :: BenchmarkBundle -> IO (Either FibonError RunData)
runBundle bb = runFibonMonad bb $ do
  RunComplete   rr <- runAction Run
  return rr

prepNofibBundle :: BenchmarkBundle -> IO (Either FibonError ())
prepNofibBundle bb = runFibonMonad bb $ do
  prepRun pathToBench

runFibonMonad :: BenchmarkBundle
              -> ErrorT FibonError (ReaderT BenchmarkBundle IO) a
              -> IO (Either FibonError a)
runFibonMonad bb a = runReaderT (runErrorT a) bb

runAction :: Action -> FibonRunMonad ActionResult
runAction Sanity = do
  sanityCheck
  return SanityComplete
runAction Build = do
  runConfigure
  r <- runBuild
  return $ BuildComplete r
runAction Run = do
  prepRun pathToExeBuildDir
  r <- runRun
  return $ RunComplete r

sanityCheck :: FibonRunMonad ()
sanityCheck = do
  bb <- ask
  let bmPath = pathToBench bb
  io $ Log.info ("Checking for directory:\n"++bmPath)
  bdExists <- io $ doesDirectoryExist bmPath
  unless bdExists (throwError $ pathDoesNotExist bmPath)
  io $ Log.info ("Checking for cabal file in:\n"++bmPath)
  dirContents <- io $ getDirectoryContents bmPath
  let cabalFile = find (".cabal" `isSuffixOf`) dirContents
  case cabalFile of
    Just f  -> do io $ Log.info ("Found cabal file: "++f)
                  checkForExpectedOutFiles
    Nothing -> throwError cabalFileDoesNotExist
  where
  pathDoesNotExist bmP  = SanityError("Directory:\n"++bmP++" does not exist")
  cabalFileDoesNotExist = SanityError "Can not find cabal file"

checkForExpectedOutFiles :: FibonRunMonad ()
checkForExpectedOutFiles = do
  bb <- ask
  io $ Log.info "Checking for diff files"
  let expectedOut = (output . benchDetails) bb
      fs = diffFiles expectedOut
  missingFiles <- io $ filterM (missing bb) fs
  case missingFiles of
    [] -> return ()
    ms -> throwError $ SanityError("Missing expected output files: "++show ms)
  where
  missing bb f = do
    Log.info $ "Checking for expected output file: " ++ f
    e1 <- doesFileExist $ (pathToAllOutputFiles bb)  </> f
    e2 <- doesFileExist $ (pathToSizeOutputFiles bb) </> f
    return (not e1 && not e2)
  diffFiles =
    catMaybes . map (\o -> case o of (_, Diff f) -> Just f ; _ -> Nothing)

runConfigure :: FibonRunMonad ()
runConfigure = do
  _ <- runCabalCommand "configure" configureFlags
  return ()

runBuild :: FibonRunMonad BuildData
runBuild = do
  time <- runCabalCommand "build" buildFlags
  size <- runSizeCommand
  return $ BuildData {buildTime = time, buildSize = size}

prepRun :: (BenchmarkBundle -> FilePath) -> FibonRunMonad ()
prepRun destSelector = do
  mapM_ (copyFiles destSelector) [
      pathToSizeInputFiles
    , pathToAllInputFiles
    , pathToSizeOutputFiles
    , pathToAllOutputFiles
    ]

runRun :: FibonRunMonad RunData
runRun =  do
  bb <- ask
  res <- io $ Runner.run bb
  io $ Log.info (show res)
  case res of
    Success s d -> return     $ RunData  {summary = s, details = d}
    Failure msg -> throwError $ RunError (summarize msg)
  where
  summarize = concat . intersperse "\n" . map  simplify
  simplify (MissingOutput f) = "Missing output file: "++f
  simplify (DiffError     _ )= "Output differs from expected."
  simplify (Timeout         )= "Timeout"
  simplify (ExitError _   a )= "Bad exit code: "++(show a)

copyFiles :: (BenchmarkBundle -> FilePath)
          -> (BenchmarkBundle -> FilePath)
          -> FibonRunMonad ()
copyFiles destSelector pathSelector = do
  bb <- ask
  let srcPath = pathSelector bb
      dstPath = destSelector bb
      cp f    = do
        io $ copyFile (srcPath </> baseName) (dstPath </> baseName)
        where baseName = snd (splitFileName f)
  dExists <- io $ doesDirectoryExist srcPath
  if not dExists
    then do io $ Log.debug (srcPath ++ " does not exist") >> return ()
    else do
      io $ Log.info ("Copying files\n  from: "++srcPath++"\n  to: "++dstPath)
      files <- io $ getDirectoryContents srcPath
      let realFiles = filter (\f -> f /= "." && f /= "..") files
      io $ Log.info ("Copying files: "++(show realFiles))
      mapM_ cp realFiles
      return ()

runCabalCommand :: String
                -> (FlagConfig -> [String])
                -> FibonRunMonad Double
runCabalCommand cmd flagsSelector = do
  bb <- ask
  let fullArgs = ourArgs ++ userArgs
      userArgs = (flagsSelector . fullFlags) bb
      ourArgs  = [cmd, "--builddir="++(pathToCabalWorkDir bb)]
  (_, time) <- timeIt $ execInDir SysTools.cabal fullArgs (pathToBench bb)
  return time

runSizeCommand :: FibonRunMonad String
runSizeCommand = do
  bb <- ask
  exec (SysTools.size) [(pathToExe bb)]

timeIt :: FibonRunMonad a -> FibonRunMonad (a, Double)
timeIt action = do
  start <- io $ getTime
  r <- action
  end <- io $ getTime
  let !delta = end - start
  return (r, delta)

io :: IO a -> FibonRunMonad a
io = liftIO

exec :: FilePath -> [String] -> FibonRunMonad String
exec exe args = exec' (createProcessCommand exe args Nothing)

execInDir :: FilePath -> [String] -> FilePath -> FibonRunMonad String
execInDir exe args dir = exec' (createProcessCommand exe args (Just dir))

exec' :: CreateProcess -> FibonRunMonad String
exec' cmd = do
  (exit, out, err) <- io $ readCreateProcessWithExitCode cmd
  io $ Log.info ("COMMAND: "++fullCommand)
  io $ Log.info ("STDOUT: \n"++out)
  io $ Log.info ("STDERR: \n"++err)
  case exit of
    ExitSuccess   -> return out
    ExitFailure _ -> throwError $ BuildError msg
  where
  msg         = "Failed running command: " ++ fullCommand 
  fullCommand = getPrettyCommand cmd

createProcessCommand :: FilePath -> [String] -> Maybe FilePath -> CreateProcess
createProcessCommand prog args workingDir =
  (proc prog args){ std_in  = CreatePipe,
                    std_out = CreatePipe,
                    std_err = CreatePipe,
                    cwd     = workingDir}

-- Runs the command specified by the CreateProcess and returns the exit code,
-- stdout and std error.
--
-- Code copied from the defition of System.Process.readProcessWithExitCode
readCreateProcessWithExitCode :: CreateProcess -> IO (ExitCode, String, String)
readCreateProcessWithExitCode cmd = do
  (Just inh, Just outh, Just errh, pid) <- createProcess cmd
  outMVar <- newEmptyMVar

  -- fork off a thread to start consuming stdout
  out  <- hGetContents outh
  _ <- forkIO $ C.evaluate (length out) >> putMVar outMVar ()

  -- fork off a thread to start consuming stderr
  err  <- hGetContents errh
  _ <- forkIO $ C.evaluate (length err) >> putMVar outMVar ()

  -- now write and flush any input
  -- in our case just close stdin since we have no input
  --when (not (null input)) $ do hPutStr inh input; hFlush inh
  hClose inh -- done with stdin

  -- wait on the output
  takeMVar outMVar
  takeMVar outMVar
  hClose outh
  hClose errh

  -- wait on the process
  ex <- waitForProcess pid

  return (ex, out, err)

getPrettyCommand :: CreateProcess -> String
getPrettyCommand cmd =
  case cmdspec cmd of
    ShellCommand s   -> s
    RawCommand   p a -> p ++ stringify a

joinWith :: a -> [[a]] -> [a]
joinWith a = concatMap (a:)

stringify :: [String] -> String
stringify = joinWith ' '

getTime :: IO Double
getTime = (fromRational . toRational) `fmap` getPOSIXTime

