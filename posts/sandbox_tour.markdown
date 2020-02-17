---
title: A Whirlwind Tour of the Apple Sandbox
date: February 17, 2020
---

No-one knows how to design truly secure software. Any sufficiently complex software _will_ contain vulnerabilities that can be abused by motivated attackers to subvert a program’s execution. Accepting this reality, the focus of the last few decades has been on developing exploit mitigation techniques such as _Address Space Layout Randomisation_ (ASLR) and _Data Execution Prevention_ (DEP) which focus on _increasing difficulty and costs_ for attackers.

![Overview: DAC vs MAC](/assets/images/sandbox_tour/dac_mac.svg)

Sandboxing is one such mitigation. It aims to reduce the damage of successful attacks on the host system. On traditional UNIX systems, programs run _as_ a user (in what’s referred to as _discretionary access control_ — DAC), inheriting all her capabilities and permissions. Most of these capabilities and permissions however are never actually required by the executing program. Sandboxing (a form of _mandatory access control_ or MAC) uses per-application security policies to limit the actions a program may take and the resources it is allowed to access; it aims to make _what a program can do_ the same as _what a program was made to do_. In this way, sandboxing implements the foundational information security principle of **least privilege**, which states that programs and users should operate using the least amount of privilege necessary to complete a certain job. Sandboxed applications – even when compromised – can access only predefined parts of the system, limiting their damage potential and requiring attackers to escape the sandbox to compromise the system itself.

Security benefits afforded by sandboxing hinge on proper configuration and understanding of the sandbox mechanism itself. No mitigation is perfect; [Mitigations have complexity, inspectability and debuggability costs](https://twitter.com/halvarflake/status/1156815950873804800). The App Sandbox is no exception: it has had a massive impact on developers scrambling to sandbox their software which was largely designed without sandboxing in mind. Apple’s sandbox implementation lacks public documentation. It “just works”, until it doesn’t. In 2018, I wrote my Master’s Thesis on the topic. In this series of posts, I am sharing what I learned in the process. My focus today is on implementation, configuration and design internals that might not be known to a wider audience.

### Threat Model
A threat model states what you (a user / a mitigation / a security system) are protecting against (and also what’s not covered). It is crucial to motivate the need for any mitigation; Unfortunately, Apple does not provide an explicit threat model for the App Sandbox. I pieced together my own version here from available marketing materials, developer-facing documentation and public sandbox-related patents. 

The App Sandbox “[is designed to contain damage to the system and the user’s data if an app becomes compromised](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AboutAppSandbox/AboutAppSandbox.html)”. However, it is “[not an anti-virus system; does not target intentionally malicious software](https://developer.apple.com/videos/play/wwdc2011/204/)”. There is  no practical difference between “intentionally malicious software” and software “compromised by malicious software”. This last quote can therefore only mean that _sandboxing in itself cannot stop malicious applications from abusing their officially granted permissions_, i.e. a malicious app can steal all user data it legitimately has access to. Sandboxing however should restrict even malicious applications from accessing resources that the app is not entitled to access. This interpretation of the former quote is consistent with Apple’s own patents on the topic, which motivate the need for sandboxing by stating that a “[program may be a malicious program that is developed to intentionally cause damages](https://patents.google.com/patent/US9280644B2/en)” and “[by restricting the execution of a program within a restricted operating environment, such damages can be greatly reduced](https://patents.google.com/patent/US9280644B2/en)”. Related patents echo this interpretation [[1](https://patents.google.com/patent/US8943550), [2](https://www.researchgate.net/publication/302691438_System_and_method_for_preserving_references_in_sandboxes)].

All programs are initially launched _non-sandboxed_ because they “[may not have had an opportunity to compile and prepare a profile to express permitted actions](https://patents.google.com/patent/US8635663)”. This is argued to be “[consistent with the \[...\] design of \[the Sandbox\] that permits intentional user actions](https://patents.google.com/patent/US8635663)”. Here, a user launching an application is interpreted as user intent. This little-known fact, which is completely absent from all official documentation, is the achilles heel of the whole system. Under _normal_ circumstances, the sandbox is initialised before transfer is controlled to application code. However, because initialisation happens in the context of the application itself, there is precious little room for error. As it stands, there is no process to ensure applications, whose metadata suggest they should run sandboxed, actually run sandboxed. I feel that this runs counter to the idea of _mandatory_ sandboxing on macOS.

## Configuration
Apple’s sandbox restricts programs in what they can do on the user’s system. As every application is unique, the sandbox theoretically has to be configured individually for each app. This cumbersome process falls to developers to do. For software distributed in the Mac App Store (MAS), sandboxing is mandatory and enforced by Apple. [Outside the MAS, sandboxing is still the exception, not the rule](https://svs.informatik.uni-hamburg.de/publications/2019/2019-11-Blochberger-State-of-the-Sandbox.pdf).

To configure per-program sandbox policies, two options are available: _SBPL_, a low-level configuration language, and _entitlements_, which offer a high-level interface and are the only officially supported sandbox configuration option.

### SBPL
The Sandbox Profile Language (SBPL) is implemented on top of the Scheme programming language. In what is referred to as an embedded domain specific language (EDSL), the base language (Scheme) is extended and augmented by custom identifiers, functions and macros to encode sandbox rules.

![SBPL Language Components](/assets/images/sandbox_tour/sbpl_components.svg)

Sandbox profiles written in SBPL consist of multiple rules specified one after the other. Later rules can overwrite preceding rules, which is commonly used to implement whitelisting profiles: Deny everything first, then selectively re-enable only what is needed. Confirmed by extensive testing, the _last applicable rule_ in a profile guides the final sandbox decision for a certain resource. Each rule consists of up to four components: An _action_, one or more _operations_, and optional _filters_ and _modifiers_. Actions decide whether to allow or deny resource accesses. Operations denote the kind of resource access the rule applies to. Filters restrict a rule’s effect to a subset of all resources, for example only to files in a certain directory. Lastly, modifiers change the default behaviour of the sandbox. By default, only denied resource accesses are logged; a modifier changes this. A few years back, [\@osxreverser](https://twitter.com/osxreverser) bothered to [document the language](https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v0.1.pdf). It’s somewhat outdated, but still very useful.

While the core SBPL language as described above is conceptually simple, SBPL profiles can include arbitrary Scheme code to dynamically _generate sandbox rules during evaluation_. Consider the following two SBPL snippets; Their compiled sandbox bytecode is identical.

```scheme
(version 1)
(allow file-read-data
	(subpath "/usr/bin")
	(subpath "/usr/local")
	(with report))
```

```scheme
(version 1)
(define (usr_plus suffix) (string-append "/usr/" suffix))
(define (file-read-rule action filter)
	(action file-read-data
			filter
			(with report)))

(file-read-rule allow
	(require-any 
		(subpath (usr_plus "bin"))
		(subpath (usr_plus "local"))))
```

Developers wishing to write SBPL sandbox profiles directly call `sandbox_init` from their application to voluntarily enable sandboxing. Well intentioned power users can use the `sandbox-exec` command line utility to run third-party software in custom sandboxes. Don’t bother doing this however; the software will not work correctly. On the off chance it does work correctly, your sandbox profile will be too permissive. 

SBPL is complex and difficult to use, even for experienced developers. Though only rarely used _directly_ nowadays, it still forms the foundation for  sandboxing on macOS and therefore remains important to understand.

### Entitlements
_Entitlements_ were introduced for reasons of usability. A “[developer does not need to know how to program or set up a set of rules for the purpose of generating a security profile](https://patents.google.com/patent/US20130283344)”. Instead, developers specify entitlements that represent the resources and capabilities their software needs to use (and hopefully no others).

Entitlements are not specific to sandboxing; They are also used for _iCloud_, _Push Notifications_ and _Apple Pay_, to name just a few. At its core, each _entitlement_ is a key-value pair, where the key is a string identifying the entitlement and the value configures the entitlement. Values can be of any type supported in property lists, including booleans, strings, dictionaries or arrays. _Entitlements_ are then simply a collection of a program’s individual capabilities.
Developers add the entitlements their applications require using Xcode or manually by editing a property list file. This list is securely embedded in the target program as part of its code signature and cannot be tampered with without invaliding an app’s cryptographic code signature. Using the `codesign` utility shows you which entitlements are embedded in binaries on your system:

```sh
$ codesign -d —entitlements :- /Applications/Calculator.app
Executable=/Applications/Calculator.app/Contents/MacOS/Calculator
<?xml version=“1.0” encoding=“UTF-8”?>
<!DOCTYPE plist PUBLIC “-//Apple//DTD PLIST 1.0//EN” “http://www.apple.com/DTDs/PropertyList-1.0.dtd”>
<plist version=“1.0”>
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.print</key>
	<true/>
</dict>
</plist>
```

Here we see `Calculator.app`’s entitlements. Applications enabling the App Sandbox using the `com.apple.security.app-sandbox` entitlement are automatically sandboxed before any application code has the chance to execute (or so in theory…). Apple mandates sandboxing for applications from the MAS and ensures new apps possess this crucial entitlement. `Calculator.app` further declares entitlements allowing it to make outbound network connections (`*.network.client`), print, as well as read _and_ write user-selected files. However, `Calculator.app` will for example never be able to use the microphone.

The list of documented (and undocumented) entitlements grows with every new macOS release. Check out [Levin’s entitlement database](http://newosxbook.com/ent.jl) and setup  [wiggle](https://github.com/ChiChou/wiggle) on your Mac to investigate further.

In contrast to SBPL, entitlements are easy to understand and use. They hide the underlying complexity of the sandbox from developers, at the expense of policy flexibility.

## Architecture
Apple’s sandbox is made up of components both in user space and in the kernel. Kernel components “[increase security and provide an efficient mechanism](https://patents.google.com/patent/US20130283344)”. The following graphic and text gives an overview of some of these components and their interactions.

![Overview: Sandboxing Architecture on macOS](/assets/images/sandbox_tour/architecture.svg)

It is important to understand that **neither profiles written in SBPL nor the entitlements a program has are the _actual_ sandbox security policy enforced at runtime**. Instead, `libsandbox` (1) is responsible for _compiling_ a sandbox profile for the application, which is then passed through the kernel (3) to the `Sandbox.kext` kernel extension (4) for enforcement. During runtime, this kernel extension interacts with `sandboxd` (2) for logging.

macOS’s XNU kernel contains a port of TrustedBSD’s _mandatory access control_ (MAC) framework, which notifies so-called _policy modules_  whenever monitored functionality is accessed by processes.
`Sandbox.kext` is one such policy module. It registers itself with the MAC framework on startup and is subsequently consulted whenever one of hundreds of monitored system calls is executed by a sandboxed program. Prior to executing the actual system call, hooks from the MAC framework call out to all registered policy modules. Each policy module can inspect the arguments and the current system state to decide whether the operation should proceed or not. If a single policy module denies an operation, the corresponding operating is cancelled and an error message is returned to the calling process ([h/t](https://dl.packetstormsecurity.net/papers/general/apple-sandbox.pdf) [\@dion](https://twitter.com/justdionysus)).

`Sandbox.kext` queries the compiled sandbox profile to check whether requested operations are allowed. The sandbox additionally supports so called _dynamic extensions_. As the name implies, these are capabilities dynamically added and removed from an application’s sandbox during its runtime. For instance, if a user drags-and-drops a file into an application, the application’s sandbox is automatically extended to allow access to this file. I did not look at dynamic extensions in more detail in my thesis.

### Sandboxing Lifecycle

![Overview: Sandboxing Lifecycle](/assets/images/sandbox_tour/lifecycle.svg)

As was already touched upon in the Threat Model, applications on macOS _always_ start out non-sandboxed. During their lifetime, they can _become_ sandboxed. Once sandboxed, an application cannot remove the restrictions again. There are two different ways for applications to end up sandboxed:

1. Given a textual SBPL sandboxing policy, programs can explicitly call `sandbox_init` or one of its variants to impose a sandbox on itself. This can be done at any point during the lifetime of a program and is completely voluntary. Though more powerful than using entitlements, it is significantly harder to configure, in addition to being deprecated and completely unsupported. Only [Apple-internal daemons](https://www.google.com/search?q=site:opensource.apple.com+%22sandbox_init%22), as well as complex third-party software such as [Mozilla’s Firefox](https://hg.mozilla.org/mozilla-central/file/tip/security/sandbox/mac/SandboxPolicyContent.h) and [Chromium](https://www.chromium.org/developers/design-documents/sandbox/osx-sandboxing-design) make use of this technique.
2. If the code signature of the program contains entitlements configuring the sandbox, `dyld`, the dynamic linker, initialises the sandbox before control is passed to the program’s entry point. Sandbox initialisation in this way is involuntary in the sense that apps have no say in the matter. For an in-depth walkthrough of how this works, check out [this article](https://geosn0w.github.io/A-Long-Evening-With-macOS's-Sandbox/) and refer to [my own revere-engineered](https://github.com/0xbf00/libsecinit) `libsystem_secinit.dylib`, which reimplements part of puzzle.  The App Sandbox is mandated for apps from the Mac App Store. Usually, if third party apps outside the store are sandboxed, they also use this technique.

## A Closer Look at `libsandbox`
No matter whether the app makes use of the App Sandbox or uses the legacy sandboxing interface, at one point `libsandbox` will be invoked to compile the security profile for the application. Conceptually, this library does two different things, though they overlap in the actual implementation. Firstly, the library contains a custom Scheme interpreter based on `TinySCHEME`, modified to handle the full SBPL language. Secondly, it contains functionality to produce (_“compile”_) the sandbox bytecode for use by the sandbox’s kernel component.

For applications using the legacy `sandbox_init` sandboxing interface directly, `libsandbox` is provided with a textual sandboxing profile written in a mixture of SBPL and Scheme. The library’s embedded interpreter _evaluates_ (i.e. _executes_) this profile because, as described previously, SBPL profiles can contain arbitrary Scheme code that _generates sandbox rules during evaluation_. Recall the two _different_ SBPL snippets shown previously that _resulted in identical bytecode_. The final ruleset generated during evaluation is then serialised and output in the opaque binary format.
 
The ability to dynamically generate sandbox rules using Scheme code forms the foundation of the _App Sandbox_, which is used by the vast majority of applications. Here, `libsandbox` is invoked by the private `AppSandbox` framework, which first collects a number of inputs for `libsandbox`:

1. _Entitlements_: These are extracted from the code signature of the application
2. _Additional Parameters_: Values such as an app’s bundle identifier and the path to the user’s home directory. These might be referenced by _sandbox snippets_ (see below) during evaluation.
3. _Sandbox Snippets_: A list of SBPL profiles to evaluate, the most important one being the abstract `application.sb` application sandboxing base profile. In addition, some of Apple’s frameworks require custom sandbox rules to function properly. These rules are specified in a `.sb` file as part of the framework bundle. When an application links against such a framework, the corresponding sandbox snippet is included in the list, too.

![Overview: Inner Workings of `libsandbox`](/assets/images/sandbox_tour/libsandbox_flow.svg)

Profile compilation for the App Sandbox is slightly more complicated compared to the legacy sandboxing mechanism. Starting out, `libsandbox` makes entitlements and additional parameters available to SBPL profiles (scripts) it evaluates. It then starts by evaluating `application.sb` (referred to as _“abstract base profile”_ in the graphic). This profile, which you can find on your system under `/System/Library/Sandbox/Profiles/application.sb`, dynamically generates sandbox rules while taking into account supplied entitlements and parameters. As shown in the graphic for example, the `(allow device-microphone)` sandbox rule is only emitted if the application possesses one of the sanctioned entitlements. Similarly, the profile references the user’s home directory (supplied as part of the /additional parameters/) using the `param` function to emit correct paths for the user’s machine. Lastly, each additional SBPL snippet is evaluated, building the final list of sandbox rules (referred to in the graphic as _“concrete app profile”_). Note that while the graphic shows the _concrete app profile_ as consisting of human-readable SBPL rules, this is a simplification. In reality the rules are encoded in complex data structures within `libsandbox`, which are finally _compiled_ into the opaque binary format for `Sandbox.kext` to use.

I motivated this post by saying that sandboxing’s effectiveness depends on proper configuration. To decide whether _anything_ is proper or not, you need to be able to look at (_audit_) it. Can you be sure what rules complex Scheme code will generate? Do you know what each entitlement _actually does_ to your sandbox? To answer these questions, you would need access to a human-readable version of the _actual sandbox profile_. Unfortunately, there is no such thing on macOS. You have to trust the system “just works”.