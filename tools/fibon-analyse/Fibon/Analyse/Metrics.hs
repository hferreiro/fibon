{-# LANGUAGE FlexibleInstances, GeneralizedNewtypeDeriving#-}
module Fibon.Analyse.Metrics (
    MemSize(..)
  , ExecTime(..)
  , Estimate(..)
  , ConfidenceInterval(..)
  , Measurement(..)
  , Metric(..)
  , PerfData(..)
  , pprPerfData
  , RawPerf(..)
  , NormPerf(..)
  , SummaryPerf(..)
  , mkPointEstimate
  , rawPerfToDouble
  , normPerfToDouble
)
where

import Data.Word
import Text.Printf

newtype MemSize    = MemSize  {fromMemSize  :: Word64}
  deriving(Eq, Num, Read, Show)
newtype ExecTime   = ExecTime {fromExecTime :: Double}
  deriving(Eq, Num, Read, Show)

data Estimate a = Estimate {
      ePoint  :: !a
    , eStddev :: !a
    , eSize   :: !Int
    , eCI     :: Maybe (ConfidenceInterval a)
  }
  deriving (Read, Show)

data ConfidenceInterval a = ConfidenceInterval {
      eLowerBound       :: !a
    , eUpperBound       :: !a
    , eConfidenceLevel  :: !Double
}
  deriving (Read, Show)

instance Functor Estimate where
  fmap f e = e {
      ePoint  = f (ePoint e)
    , eStddev = f (eStddev e)
    , eCI     = maybe Nothing (Just . fmap f) (eCI e)
  }

instance Functor ConfidenceInterval where
  fmap f c = c {
      eLowerBound = f (eLowerBound c)
    , eUpperBound = f (eUpperBound c)
  }

data Measurement a = 
    Single   a
  | Interval (Estimate a)
  deriving (Read, Show)

mkPointEstimate :: (Num b) => (b -> a) -> a -> Estimate a
mkPointEstimate mkA a = Estimate {
      ePoint  = a
    , eStddev = mkA 0
    , eSize   = 1
    , eCI     = Nothing
  }

class Metric a where
  perf :: a -> Maybe RawPerf

instance Metric (Measurement ExecTime) where
  perf (Single m)   = Just (RawTime (mkPointEstimate ExecTime m))
  perf (Interval e) = Just (RawTime  e)

instance Metric (Measurement MemSize) where
  perf (Single m)   = Just (RawSize (mkPointEstimate MemSize m))
  perf (Interval e) = Just (RawSize e)

instance Metric a => Metric (Maybe a) where
  --perf = fmap perf
  perf Nothing  = Nothing
  perf (Just x) = perf x

data PerfData =
    NoResult
  | Raw RawPerf
  | Norm NormPerf
  | Summary SummaryPerf
  deriving(Read, Show)

data RawPerf =
    RawTime (Estimate ExecTime)
  | RawSize (Estimate MemSize)
  deriving(Read, Show)

data NormPerf =
    Percent (Estimate Double) -- ^ (ref  / base) * 100
  | Ratio   (Estimate Double) -- ^ (base / ref)
  deriving(Read, Show)

data SummaryPerf =
    GeoMean   NormPerf
  | ArithMean RawPerf
  deriving(Read, Show)

pprPerfData :: Bool -> PerfData -> String
pprPerfData _ NoResult    = "--"
pprPerfData u (Raw  r)    = pprRawPerf  u r
pprPerfData u (Norm n)    = pprNormPerf u n
pprPerfData u (Summary s) = pprSummaryPerf u s

pprNormPerf :: Bool -> NormPerf -> String
pprNormPerf u (Percent d) =
  printf "%0.2f%s" ((ePoint d)  - 100) (pprUnit u "%")
pprNormPerf _ (Ratio d) =
  printf "%0.2f"    (ePoint d)

pprRawPerf :: Bool -> RawPerf -> String
pprRawPerf u (RawTime t)    =
  printf "%0.2f%s"  ((fromExecTime . ePoint) t) (pprUnit u "s")
pprRawPerf u (RawSize s)    =
  printf "%0d%s"
    (round (fromIntegral ((fromMemSize . ePoint) s) / 1000 :: Double)::Word64)
    (pprUnit u "k")
{-
pprRawPerf u (RawTimeInterval e) = printf "%0.2f%s"
                              ((fromExecTime . ePoint) e)
                              (pprPlusMinus e fromExecTime)
                              (pprUnit u "s")
pprRawPerf u (RawSizeInterval e) = printf "%d%s%s"
                              ((fromMemSize . ePoint) e)
                              (pprPlusMinus e fromMemSize)
                              (pprUnit u "k")

pprPlusMinus :: Real b => Estimate a -> (a -> b) -> String
pprPlusMinus e f = printf "%c%0.2d" (chr 0xB1) ((realToFrac spread)::Double)
  where spread = abs ((f . ePoint) e) - ((f . eLowerBound) e)
-}
pprSummaryPerf :: Bool -> SummaryPerf -> String
pprSummaryPerf u (GeoMean n)   = pprNormPerf u n
pprSummaryPerf u (ArithMean r) = pprRawPerf  u r

pprUnit :: Bool -> String -> String
pprUnit True s = s
pprUnit _    _ = ""

rawPerfToDouble :: RawPerf -> Double
rawPerfToDouble (RawTime t) = (fromExecTime . ePoint) t
rawPerfToDouble (RawSize s) = (fromIntegral . fromMemSize . ePoint) s

normPerfToDouble :: NormPerf -> Double
normPerfToDouble (Percent p) = ePoint p
normPerfToDouble (Ratio   r) = ePoint r

