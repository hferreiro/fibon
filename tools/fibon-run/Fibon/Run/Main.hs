module Main (
  main
)
where 
import Control.Monad
import Control.Exception
import qualified Data.ByteString as B
import Data.Char
import Data.List
import Data.Maybe
import Data.Serialize
import Data.Time.Clock
import Data.Time.Format
import Data.Time.LocalTime
import Fibon.Benchmarks
import Fibon.Result
import Fibon.Run.Actions
import Fibon.Run.CommandLine
import Fibon.Run.Config
import Fibon.Run.Manifest
import Fibon.Run.BenchmarkBundle
import qualified Fibon.Run.Log as Log
import System.Directory
import System.Exit
import System.Environment
import System.FilePath
import System.Locale
import System.Time
import Text.Printf


main :: IO ()
main = do
  opts <- parseArgsOrDie
  currentDir <- getCurrentDirectory
  initConfig  <- selectConfig (optConfig opts)
  let runConfig  = mergeConfigOpts initConfig opts
      workingDir = currentDir </> "run"
      benchRoot  = currentDir </> "benchmarks/Fibon/Benchmarks"
      logPath    = currentDir </> "log"
      action     = optAction opts
  uniq       <- chooseUniqueName workingDir (configId runConfig)
  (logFile, showFile, summaryFile, binFile) <- Log.setupLogger logPath logPath uniq
  startTime <- timeStamp
  progEnv <- getEnvironment
  Log.notice ("Starting Run at   " ++ prettyTimeStamp startTime)
  Log.notice ("  log            : " ++ logFile)
  Log.notice ("  result(binary) : " ++ binFile)
  Log.notice ("  result(text)   : " ++ showFile)
  Log.notice ("  result(summary): " ++ summaryFile)
  let bundles = makeBundles runConfig workingDir benchRoot uniq progEnv
  results <- mapM (runAndReport action) bundles
  (B.writeFile binFile . encode) (catMaybes results)
  endTime <- timeStamp
  Log.notice ("Finished Run at " ++ formatEndTime startTime endTime)
  Log.notice ("  log            : " ++ logFile)
  Log.notice ("  result(binary) : " ++ binFile)
  Log.notice ("  result(text)   : " ++ showFile)
  Log.notice ("  result(summary): " ++ summaryFile)

parseArgsOrDie :: IO Opt
parseArgsOrDie = do
  args <- getArgs
  case parseCommandLine args of
    Left  msg  -> putStrLn msg >> exitFailure
    Right opts -> do
      case optHelpMsg opts of
        Just msg -> putStrLn msg >> exitSuccess
        Nothing  -> return opts

type RunResult = Maybe FibonResult
type RunCont a = (a -> IO RunResult)
runAndReport :: Action -> BenchmarkBundle -> IO RunResult
runAndReport action bundle = do
  Log.notice $ "Benchmark: "++ (bundleName bundle)++ " action="++(show action)
  case action of
    Sanity -> run sanityCheckBundle  (const $ return Nothing)
    Build  -> run buildBundle        (\(BuildData time _size) -> do
                Log.info (printf "Build completed in %0.2f seconds" time)
                return Nothing
              )
    Run    -> run runBundle          (\fr@(FibonResult n _bd rd) -> do
                Log.result(show fr)
                Log.summary(printf "%s %.4f" n ((meanTime . summary) rd))
                return (Just fr)
              )
  where
  run :: Show a => ActionRunner a -> RunCont a -> IO RunResult
  run = runAndLogErrors bundle

runAndLogErrors :: Show a
                => BenchmarkBundle
                -> ActionRunner a
                -> RunCont a
                -> IO RunResult
runAndLogErrors bundle act cont = do
  result <- try (act bundle)
  -- result could fail from an IOError, or from a failure in the RunMonad
  case result of
    Left  ioe -> logError (show (ioe :: IOError)) >> return Nothing
    Right res ->
      case res of
        Left  e -> logError (show e) >> return Nothing
        Right r -> cont r
   where
   name = bundleName bundle
   logError s = do Log.warn $ "Error running: "  ++ name
                   Log.warn $ "        =====> "  ++ s

selectConfig :: ConfigId -> IO RunConfig
selectConfig configName =
  case find ((== configName) . configId) configManifest of
    Just c  -> do return c
    Nothing -> do
      Log.error $ "Unknown config: "       ++ configName
      Log.error $ "Available configs:\n  " ++ configNames
      exitFailure
  where configNames = concat (intersperse "\n  " $ map configId configManifest)

makeBundles :: RunConfig
            -> FilePath  -- ^ Working directory
            -> FilePath  -- ^ Benchmark base path
            -> String    -- ^ Unique Id
            -> [(String, String)] -- ^ Environment variables
            -> [BenchmarkBundle]
makeBundles rc workingDir benchRoot uniq progEnv = map bundle bms
  where
  bundle (bm, size, tune) =
    mkBundle rc bm workingDir benchRoot uniq size tune progEnv
  bms = sort
        [(bm, size, tune) |
                      size <- (sizeList rc),
                      bm   <- expandBenchList $ runList rc,
                      tune <- (tuneList rc)]

expandBenchList :: [BenchmarkRunSelection] -> [FibonBenchmark]
expandBenchList = concatMap expand
  where
  expand (RunSingle b) = [b]
  expand (RunGroup  g) = filter (\b -> benchGroup b == g) allBenchmarks

chooseUniqueName :: FilePath -> String -> IO String
chooseUniqueName workingDir configName = do
  wdExists <- doesDirectoryExist workingDir
  unless wdExists (createDirectory workingDir)
  dirs  <- getDirectoryContents workingDir
  let numbered = filter (\x -> length x > 0) $ map (takeWhile isDigit) dirs
  case numbered of
    [] -> return $ format (0 :: Int)
    _  -> return $ (format . (+1) . read . last . sort) numbered
  where
  format :: Int -> String
  format d = printf "%03d.%s" d configName

mergeConfigOpts :: RunConfig -> Opt -> RunConfig
mergeConfigOpts rc opt = rc {
      tuneList   = maybe (tuneList rc) (:[]) (optTuneSetting opt)
    , sizeList   = maybe (sizeList rc) (:[]) (optSizeSetting opt)
    , runList    = maybe (runList  rc)   id  (optBenchmarks  opt)
    , iterations = maybe (iterations rc) id  (optIterations  opt)
  }

type TimeStamp = (ClockTime, LocalTime)
timeStamp :: IO TimeStamp
timeStamp = do
  tz <- getCurrentTimeZone
  t  <- getCurrentTime
  ct <- getClockTime
  return $ (ct, utcToLocalTime tz t)

prettyTimeStamp :: TimeStamp -> String
prettyTimeStamp (_,lt) = formatTime defaultTimeLocale "%F %T" lt

prettyTimeDiff :: TimeStamp -> TimeStamp -> String
prettyTimeDiff (ct1,_) (ct2,_) =
  timeDiffToString . normalizeTimeDiff $ diffClockTimes ct2 ct1

formatEndTime :: TimeStamp -> TimeStamp -> String
formatEndTime startT endT =
  prettyTimeStamp endT ++ " (completed in " ++ prettyTimeDiff startT endT ++")"

{-
dumpConfig :: RunConfig -> IO ()
dumpConfig rc = do
  --putStrLn $ show $ map (uncurry benchInstance) $ sort bms
  putStrLn $ show bms
  mapM_ (dumpInstance rc) bms
  where
  bms = sort
        [(bm, size, tune) |
                      size <- (sizeList rc),
                      bm   <- expandBenchList $ runList rc,
                      tune <- (tuneList rc)]

dumpInstance :: RunConfig -> (FibonBenchmark, InputSize, TuneSetting)->IO ()
dumpInstance rc inst@(bm, size, tune) = do
  putStrLn (take 68 $ repeat '-')
  putStrLn (show inst)
  putStrLn (take 68 $ repeat '-')
  putStrLn (show $ mkFlagConfig rc bm size tune)

-}
