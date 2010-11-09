Fibon in a Flash
===================================================================
    $ git clone git://github.com/dmpots/fibon.git
    $ cd fibon
    $ git submodule update --init benchmarks
    $ cabal configure && cabal build
    $ ./dist/build/fibon-run/fibon-run

Introduction
===================================================================
Fibon is a set of tools for running and analyzing benchmark programs in
Haskell. Most importantly, it includes an optional set of new [benchmarks][2]
including many programs taken from the [Hackage][1] open source repository.

Fibon is a pure Haskell framework for running and analyzing benchmarks. Cabal
is used for building the benchmarks, and the benchmark harness, configuration
files, and benchmark descriptions are all written in Haskell. The benchmark
descriptions and run configurations are all statically compiled into the
benchmark runner to ensure that configuration errors are found at compile
time.

The Fibon tools are not tied to any compiler infrastructure and can build
benchmarks using any compiler supported by cabal. However, there are some
extra features available when using GHC to build the benchmarks:

  * Support in config files for inplace GHC HEAD builds
  * Support in `fibon-run` for collecting GC stats from GHC compiled programs
  * Support in `fibon-analyse` for reading GC stats from Fibon result files

Benchmarks
------------------
Fibon makes it easy to use either the Fibon benchmarks or your own
set of benchmarks. Benchmarks are stored in the
`benchmarks/Fibon/Benchmarks` directory. This directory is setup as
a [git submodule][3] which means you can easily grab the standard
suite or use a suite kept under your own source control.

The default suite of benchmarks is stored in the
[fibon-benchmarks][2] repository on github.

Benchmark Groups
------------------
Benchmarks are named and organized into groups based on the filesystem
organization. For example, a benchmark in the directory
`benchmarks/Fibon/Benchmarks/Hackage/Agum` will have the name `Agum`
an be in the benchmark group `Hackage`.

Executables
------------------
The fibon package builds three tools:

1. `fibon-run` - runs the benchmarks
2. `fibon-analyze` - analyzes the results of a run
3. `fibon-init` - utility used when adding new benchmarks

Size and Tune
------------------
Fibon benchmarks can be run with two different input sizes: `Test` and `Ref`.
The `Test` size is useful to make sure that a benchmark can run successfully,
but will not give meaningful timings. The `Ref` size should be used when
reporting results.

Fibon benchmarks can be run under two different tune settings (e.g.
compiler optimization settings). The `Base` and `Peak` settings can
be configured anyway you want to make the desired comparison.

Directory Structure
--------------------
Source directories

    ./benchmarks -- benchmark code
    ./config     -- config files
    ./lib        -- common files used by several executables
    ./tools      -- source code for executables

Working directories

    ./log        -- logging output from benchmark runs
    ./run        -- working directory for benchmark runs

Getting the Benchmarks
===================================================================
The benchmarks are kept in a separate repository as a git
submodule. You can get the Fibon benchmarks by updating the
submodule from within your Fibon working directory

    $ git submodule update --init benchmarks

This will checkout the benchmarks from the [fibon-benchmarks][2]
repository and place them in your working copy.

Running Benchmarks
===================================================================
The available benchmarks and configurations are discovered when the
Fibon package is configured. Benchmarks are searched for in the
`benchmarks/Fibon/Benchmarks` directory and configuration files are
searched for in the `config` directory. If a configuration file or
benchmark is added, you will need to re-run `cabal configure` to
make them available to the fibon-run tool.

Configuration
---------------
Fibon comes with a default configuration. The default configuration
will run all benchmarks with the `Base` setting of `-O0` and a
`Peak` setting of `-O2` on the `Ref` size. A configuration file can
be used to specify more complicated configurations.

You can get some example configuration by doing
    $ git submodule update --init config

This will checkout a repository of config files. Note that currently
these files contain some user and machine-specific configurations,
but should be a useful starting point.

You can also command line options to selectively run benchmarks,
groups, sizes, and tune settings as described below.

Running
---------------
Benchmarks are run with the `fibon-run` tool. Running `fibon-run`
with no arguments will use the default config file. An alternate
config file can be specified with the `-c` flag. Also, you can give
a list of benchmarks or groups to run on the command line. Use
`--help` to see a full list of options.

Running the benchmarks will produce some logging to standard out and
create four output files in the `log` directory.

1. `*.LOG` - the full log of the run
2. `*.SUMMARY` - the mean runtimes of each benchmark
3. `*.RESULTS`  - the full results in binary format (pass to `fibon-analyse`)
4. `*.RESULTS.SHOW` - the full results in text format (pass to `fibon-analyse`)

Analyzing Benchmark Results
===================================================================
Benchmarks can be analyzed by the `fibon-analyse` tool.

    $ fibon-analyse log/000.default.RESULTS
or

    $ fibon-analyse log/000.default.RESULTS.SHOW

The binary results (`.RESULT`) file is much faster to parse. It
contains a serialization of a list of `FibonResult` structures. The
`.SHOW` file contains a `FibonResult` on each line which can be
parsed by using the `read` function.

Adding New Benchmarks
===================================================================

New benchmarks are added by putting the appropriate files in the
`benchmarks/Fibon/Benchmarks` directory. Each folder in this directory
represents a benchmark group. The benchmarks and groups are found at
configuration time (i.e. when running `cabal configure` for the fibon
package). You can exclude a benchmark or a group by prefixing the name with
and underscore (`_`).

To add a new benchmark create a new folder in a benchmark group. If the
benchmark program has been cabalized, you can typically just do a
`cabal unpack` of the benchmark. The benchmark folder must contain:

  1. A cabal file describing how to build the benchmark
  2. A benchmark description for Fibon stored in `Fibon/Instance.hs`

The `fibon-init` tool will read a cabal file from the current directory and generate the Fibon subfolder and a stub `Instance.hs` file.

The `Fibon` subfolder of a benchmark contains all of the data that Fibon needs
to build and execute the benchmark. The benchmark instance file describes any
requried build flags, inputs, and outputs for the benchmark. It is a standard
Haskell module that must export the `mkInstance` function. The `mkInstance`
function takes a benchmark size and returns a `BenchmarkInstance` structure.
An example instance file is show below.

    module Fibon.Benchmarks.Hackage.Bzlib.Fibon.Instance(
      mkInstance
    )
    where
    import Fibon.BenchmarkInstance

    sharedConfig = BenchmarkInstance {
        flagConfig = FlagConfig {
            configureFlags = []
          , buildFlags     = []
          , runFlags       = []
          }
        , stdinInput     = Nothing
        , output         = []
        , exeName        = "hsbzip"
      }
    flgCfg = flagConfig sharedConfig

    mkInstance Test = sharedConfig {
          flagConfig = flgCfg {
              runFlags = ["bzlib.cabal.bz2"]
          }
          , output    = [(OutputFile "bzlib.cabal.bz2.roundtrip",
                          Diff       "bzlib.cabal.bz2")]
        }
    mkInstance Ref  = sharedConfig {
          flagConfig = flgCfg {
              runFlags = ["mito.aa.bz2"]
          }
          , output   = [(OutputFile "mito.aa.bz2.roundtrip",
                         Diff       "mito.aa.bz2")]
        }

The input and expected output data should also be stored in the `Fibon`
subdirectory of the benchmark. When the benchmark is run, the contents of the
input and output directories for the benchmark size will be copied to the
working directory where the benchmark is run. There can also be an `all`
directory which whose data will be copied for all input sizes. None of the
data directories are required, but if they exist they must be organized like
this:

        data/all/input
        data/all/output
        data/ref/input
        data/ref/output
        data/test/input
        data/test/output

Benchmark Notes
===================================================================
Ghc612
  The Repa and Dph groups will not work properly.

Ghc610
  The Repa and Dph groups will not work properly.
  
  ChameneosRedux
    Does not work with -O0. Gets "thread blocked indefinitely"
    exception

  Mandelbrot
    The Test size gives different result, but the Ref size is ok.
    Think it is just some kind of floating point wibbles.

[1]: http://hackage.haskell.org
[2]: http://github.com/dmpots/fibon-benchmarks
[3]: http://www.kernel.org/pub/software/scm/git/docs/user-manual.html#submodules
