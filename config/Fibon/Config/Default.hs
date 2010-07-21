module Fibon.Config.Default (
  config
)
where
import Fibon.RunConfig
import Fibon.Benchmarks
import Fibon.InputSize
import Fibon.ConfigMonad

config :: RunConfig
config = RunConfig {
    configId = "default"
  , runList  = [RunGroup SpectralGroup]
  , sizeList = [Test]
  , tuneList = [Base, Peak]
  , iterations = 3
  , flagsBuilder = flags
  }

flags :: FlagBuilder
flags ConfigTuneDefault ConfigBenchDefault = do
  append ConfigureFlags "--ghc"
  append ConfigureFlags "--disable-optimization"
  done

flags (ConfigTune Base) ConfigBenchDefault = do
  append  ConfigureFlags "--ghc-options -O0"

flags (ConfigTune Peak) ConfigBenchDefault = do
  append  ConfigureFlags "--ghc-options -O2"

flags (ConfigTuneDefault) (ConfigBench Scc)= do
  append  ConfigureFlags "--ghc-options -O3"

flags _ _ = do
  done
