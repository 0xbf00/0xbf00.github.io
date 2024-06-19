## Installation

```sh
$ cabal build
```

## Usage

````sh
$ cabal run
Missing: COMMAND

Usage: ubrigens [-v|--verbose] COMMAND

  ubrigens - Static site compiler created with Hakyll

Available options:
  -h,--help                Show this help text
  -v,--verbose             Run in verbose mode

Available commands:
  build                    Generate the site
  check                    Validate the site output
  clean                    Clean up and remove cache
  deploy                   Upload/deploy your site
  preview                  [DEPRECATED] Please use the watch command
  rebuild                  Clean and build again
  server                   Start a preview server
  watch                    Autocompile on changes and start a preview server.
                           You can watch and recompile without running a server
                           with --no-server.

```

```sh
# To interactively test changes
$ cabal run ubrigens watch
# To deploy new version
```