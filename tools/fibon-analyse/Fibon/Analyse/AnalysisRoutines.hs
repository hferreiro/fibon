module Fibon.Analyse.AnalysisRoutines(
    noAnalysis
  , ghcStatsAnalysis
  , Analysis(..)
)
where

import Data.ByteString(ByteString)
import Fibon.Result
import Fibon.Analyse.ExtraStats
import Fibon.Analyse.Metrics
import Fibon.Analyse.Parse
import Fibon.Analyse.Result

data Analysis a = Analysis {
      fibonAnalysis :: (FibonResult  -> IO FibonStats)-- ^ RunData analyser
    , extraParser   :: (ByteString -> Maybe a)        -- ^ extraStats parser
    , extraAnalysis :: ([a]     -> IO    a)           -- ^ extraStats analyser
  }

noAnalysis :: Analysis a
noAnalysis  = Analysis {
      fibonAnalysis  = return . getStats
    , extraParser    = const Nothing
    , extraAnalysis  = return . head
  }
  where 
    getStats fr = FibonStats {
          compileTime = Single $ ExecTime ((buildTime . buildData) fr)
        , binarySize  = Single $ getSize (sizeData fr)
        , wallTime    = Single $ ExecTime ((meanTime . summary . runData) fr)
      }
    getSize s = maybe (MemSize 0) MemSize (parseBinarySize s)
    sizeData  = buildSize . buildData

ghcStatsAnalysis :: Analysis GhcStats
ghcStatsAnalysis = noAnalysis {
      extraParser   = parseGhcStats
    , extraAnalysis = return . ghcStatsSummary
  }
--TODO: make extraAnalysis for GhcStats acutally do some analysis
--makeAnalysis :: Analysis a -> (String -> Maybe b) -> Analysis b



