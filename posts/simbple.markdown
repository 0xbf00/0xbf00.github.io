---
title: "It's Simbple: Peeking Inside App Sandbox Profiles"
date: February 21, 2020
---

I concluded [my previous post](/posts/sandbox_tour.html) by motivating that we should be able to audit the sandbox configurations of apps we run. Because of the way the App Sandbox works on macOS, this means we need access to a human-readable version of the sandbox profile _generated_ by `libsandbox.dylib`. Unfortunately, this is not something that Apple’s software currently allows for.

There have been numerous projects that _decompile_ sandbox bytecode back to a human-readable representation, most notably Blazakis's [XNUSandbox project](https://github.com/dionthegod/XNUSandbox), Esser's [sb2dot](https://github.com/sektioneins/sandbox_toolkit/tree/master/sb2dot), work by [argp](https://argp.github.io/research/) and [SandBlaster](https://github.com/malus-security/sandblaster). These tools are necessary on iOS; Profiles there are only available in binary form. Most of these tools however suffer from two problems. Firstly, they are hard to keep up to date, as even small changes to the bytecode format break the tooling. Secondly, most of the tools do not produce syntactically valid SBPL and therefore cannot be recompiled. As a result, it is not possible to verify their output.

On macOS, things are generally simpler: Rather than reverse engineering the sandbox bytecode format, I reverse engineered how `libsandbox` internally handles entitlements, sandbox snippets and parameters to evaluate and compile sandbox profiles.

The result of this research is [`simbple`](https://github.com/0xbf00/simbple), a tool that reimplements the profile evaluation process done in `libsandbox` but outputs verifiably correct, human-readable SBPL.

Note that [\@sdotknight rightfully points](https://twitter.com/sdotknight/status/1230222846120644608) out that there is a platform profile that _also_ affects sandboxing on macOS. My approach here only considers the sandbox profile generated in userland and does not consider the platform profile, which is embedded inside of `Sandbox.kext`.

## The Anatomy of Container.plist files on macOS
`simbple` takes as input an apps’ `Container.plist` file, which can be found under `~/Library/Containers/bundle_id/`. This binary-encoded plist file contains lots of useful information (_note_: launch the target app once to generate the file). Follow along using:

```bash
# Built-in tools, always available
$ plutil -convert xml1 /path/to/Container.plist -o -
# Levin's excellent tools. Display the information in a simpler format.
$ jlutil /path/to/Container.plist
```

Likely taking up the most space in any `Container.plist`, the `SandboxProfileData` key holds the base64-encoded binary sandbox profile compiled by `libsandbox`.

Grouped under `SandboxProfileDataValidationInfo` are inputs `libsandbox` uses to compile sandbox profiles:

1. `SandboxProfileDataValidationParametersKey` — Contains several “global variables” such as the user’s home directory (stored as `_HOME`), her username (`_USER`) and various (auto-generated) paths to the application bundle and temporary directories.
2.  `SandboxProfileDataValidationRedirectablePathsKey` — approved paths that may be accessed through symlinks
3. `SandboxProfileDataValidationEntitlementsKey` — An app’s entitlements.
4. `SandboxProfileDataValidationSnippetDictionariesKey` — A list of sandbox _snippets_ (see previous post) included in the final profile. Each snippet is described by two keys, though only one of them — `AppSandboxProfileSnippetPathKey` — is important here. It specifies the file system path to the snippet.

## Using `simbple`
`simbple` uses existing `Container.plist` files to reuse the same parameters that were initially used by the system. This simplifies the design of the tool.

```bash
$ simbple --help
Usage: simbple [OPTION...] CONTAINER_METADATA
Evaluate a SBPL (+ Scheme) profile

  -o, --output=FILE          Output file
  -p, --profile=PROFILE      Base profile to evaluate. Defaults to
                             application.sb profile.
      --platforms=PLATFORM   sierra, high_sierra, mojave (default), catalina

 Output formats:
      --json                 Output as JSON
      --scheme               Output as SCHEME / SBPL

 Misc options:
      --patch                Patch the output profile to log all statements.
      --verify               Verify semantic correctness of generated results

  -?, --help                 Give this help list
      --usage                Give a short usage message
  -V, --version              Print program version

Mandatory or optional arguments to long options are also mandatory or optional
for any corresponding short options.

The output is a simplified SBPL profile that can be analysed, modified and
compiled as is.
```

In its simplest form, simply invoke `simbple` with a path to the `Container.plist` file of the app you are interested in. Doing so will spit out the SBPL profile of the target app:

```bash
$ simbple ~/Library/Containers/com.apple.calculator/Container.plist
(version 1)
(deny
    default
)
(allow
    mach-register
    (local-name-prefix "")
)
(allow
    mach-lookup
    (xpc-service-name-prefix "")
)
# > 1800 lines follow on my system
```
The resulting sandbox profiles can be manually audited and modified, automatically patched or simply be compiled to profile bytecode using [Stefan Esser’s tool](https://github.com/sektioneins/sandbox_toolkit/tree/master/compile_sb). The results are useful not only to security researchers interested in studying the sandbox, but also for example to developers debugging their sandboxed applications.

To verify that results are _correct_ — meaning compiling the output results in identical sandbox bytecode to `libsandbox`’s result — use the `--verify` option. This is yet another benefit of using existing `Container.plist` files. We can use the `SandboxProfileData` data as ground truth to check against. Sandbox compilation is still a ([mostly](https://github.com/0xbf00/simbple/blob/e4211c3428a417e351b7487990d00db2a71b3b69/src/sb/verify.c#L46)) deterministic process.

```bash
$ simbple ~/Library/Containers/com.apple.calculator/Container.plist -o /dev/null --verify
$ echo $?
0 # Verification succeeded.
```



## A Teaser: The Story of CVE-2018-4184
[macOS 10.13.5 fixed CVE-2018-4184](https://support.apple.com/en-us/HT208849), an issue with “the handling of microphone access” I reported in 2018:

```
*Speech*
	Available for: macOS High Sierra 10.13.4
	Impact: A sandboxed process may be able to circumvent sandbox restrictions
	Description: A sandbox issue existed in the handling of microphone access. This issue was addressed with improved handling of microphone access.
	CVE-2018-4184: Jakob Rieck (@0xdead10cc) of the Security in Distributed Systems Group, University of Hamburg
```

What was the problem? Virtually every app — no matter their entitlements — was able to use the microphone on macOS. How did I figure this out? Well, I was developing `simbple` and thought my tool couldn’t possibly work correctly: scrolling through `Calculator.app`’s results, I noticed this line in the generated profile:

```scheme
(allow device-microphone)
```

Refer back to my previous post to see `Calculator.app`’s entitlements, which notably do not (and did not) allow the app access to the microphone. What was going on?!