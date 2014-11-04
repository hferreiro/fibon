module System_Config(
  config
)
where
import Fibon.Run.Config
import Fibon.Benchmarks
import Control.Monad(when)
import Data.Maybe(isJust)

config :: RunConfig
config = RunConfig {
    configId = "system-A0.5m"
  , runList  = map RunSingle hackage
  , sizeList = [Test, Train, Ref]
  , tuneList = [Peak]
  , iterations = 1
  , configBuilder = build
  }
  where
    --shootout = filter (\b -> benchGroup b == Shootout) allBenchmarks
    hackage = filter (\b -> benchGroup b == Hackage && b /= Gf) allBenchmarks

collectStats :: Bool
collectStats = True

build :: ConfigBuilder
--
-- Default Settings for All Benchmarks
--
build ConfigTuneDefault ConfigBenchDefault = do
  setTimeout $ Limit 0 15 0
  append ConfigureFlags "--ghc-option=-rtsopts"

  maybe done
        useGhcDir
        (Just "/usr/bin")

  -- Setup stats collection
  if collectStats
    then do
    collectExtraStatsFrom  "ghc.stats"
    append RunFlags "+RTS -A0.5m -tghc.stats --machine-readable -RTS"
    else
    done

--
-- Default Settings for Specific Benchmarks
--
build (ConfigTuneDefault) (ConfigBench QuickHull) = do
  append RunFlags "+RTS -K64M -RTS"

build (ConfigTuneDefault) (ConfigBench Qsort) = do
  append RunFlags "+RTS -K16M -RTS"

--
-- Base Tune Settings
--
build (ConfigTune Base) ConfigBenchDefault = do
  append ConfigureFlags "--disable-optimization"

build (ConfigTune Base) (ConfigBench BinaryTrees) = do
  append RunFlags "+RTS -K64M -RTS"

build (ConfigTune Base) (ConfigBench Palindromes) = do
  append RunFlags "+RTS -K256M -RTS"

build (ConfigTune Base) (ConfigBench TernaryTrees) = do
  append RunFlags "+RTS -K16M -RTS"

build (ConfigTuneDefault) (ConfigBench Cpsa) = do
  append BuildFlags "--ghc-option=-fcontext-stack=42"

--
-- Peak Tune Settings
--
build (ConfigTune Peak) ConfigBenchDefault = do
  append ConfigureFlags "--enable-optimization=2"

build (ConfigTune Peak) (ConfigBench BinaryTrees) = do
  append RunFlags "+RTS -K32M -RTS"

build (ConfigTune Peak) (ConfigBench Palindromes) = do
  append RunFlags "+RTS -K128M -RTS"

build (ConfigTune Peak) (ConfigBench TernaryTrees) = do
  append RunFlags "+RTS -K16M -RTS"

build _ _ = done
