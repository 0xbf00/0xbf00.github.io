---
title: "\"Linking a Microphone\" Or: The Story of CVE-2018-4184"
date: February 26, 2020
---

Developing and testing [`simbple`](https://github.com/0xbf00/simbple), my SBPL interpreter, at the beginning of 2018, I thought my tool couldn’t possibly work correctly: scrolling through the results it yielded for `Calculator.app` — needless to say my main test application — I noticed this line in the generated profile:

```scheme
(allow device-microphone)
```

Trying to figure out what went wrong, I created a minimal test case: taking `Calculator.app`’s Container file, I reduced it down to its core, stripping most entitlements, as many variables as possible and all sandbox snippets except for the `application.sb` base profile. To my surprise, the line displayed above disappeared. Eventually, I realised that the sandbox snippet associated with `SpeechRecognitionCore.framework` was to blame. This is what the snippet looked like:

```scheme
;;
;; Speech Recognition Core framework - sandbox profile
;; Copyright (c) 2013 Apple Inc. All Rights reserved.
;;
;; WARNING: The sandbox rules in this file currently constitute
;; Apple System Private Interface and are subject to change at any time and
;; without notice. The contents of this file are also auto-generated and not
;; user editable; it may be overwritten at any time.
;;
(allow device-microphone)
```

But what does `SpeechRecognitionCore` have to do with `Calculator.app`?

## A Second Look at Sandbox Snippets
[In my introductory post](/posts/sandbox_tour.html) about the App Sandbox, I listed the inputs `libsandbox` receives to build the sandbox profile for a specific app. Among them were _sandbox snippets_, a list of SBPL profiles that are evaluated to build the final list of sandbox rules. In addition to `application.sb`, which forms the foundation of the App Sandbox, your app can depend on external (system) frameworks and libraries. These frameworks may require additional, custom sandbox rules to function properly, which are specified in the  `Resources/framework.sb` file as part of the framework bundle. Note that while such additional sandbox rules theoretically are required by that framework only, the sandbox works on a per-process basis. Because application and framework code runs in the same process, they also affect the application.

On my system, `Calculator.app` links with 11 frameworks / libraries

```bash
$ otool -L /Applications/Calculator.app/Contents/MacOS/Calculator 
/Applications/Calculator.app/Contents/MacOS/Calculator:
	/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit (compatibility version 45.0.0, current version 1671.40.104)
	/System/Library/Frameworks/Cocoa.framework/Versions/A/Cocoa (compatibility version 1.0.0, current version 23.0.0)
	/System/Library/PrivateFrameworks/SpeechDictionary.framework/Versions/A/SpeechDictionary (compatibility version 1.0.0, current version 1.0.0)
	/System/Library/PrivateFrameworks/SpeechObjects.framework/Versions/A/SpeechObjects (compatibility version 1.0.0, current version 1.0.0)
	/System/Library/PrivateFrameworks/Calculate.framework/Versions/A/Calculate (compatibility version 1.0.0, current version 1.0.0)
	/System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices (compatibility version 1.0.0, current version 50.1.0)
	/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore (compatibility version 1.2.0, current version 1.11.0)
	/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation (compatibility version 300.0.0, current version 1570.13.0)
	/usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)
	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1252.250.1)
	/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation (compatibility version 150.0.0, current version 1570.13.0)
```

At runtime, when linking, `dyld` will resolve and load dependencies _recursively_. Dependencies of dependencies will also be loaded into the address space of the app. When sandboxing the app, [_all_ loaded  libraries](https://github.com/0xbf00/libsecinit/blob/24962765158a9e0330f2e8732a4738b5c888d2c9/src/libsecinit.c#L207) are considered when looking for sandbox snippets (though snippets from non-system libraries are by default silently ignored).

![Overview: Sandbox Snippets on macOS](/assets/images/sandbox/snippets.svg)

This is how that snippet ended up in my output! The private `SpeechRecognitionCore.framework` is a second-order dependency of `AppKit`, the ubiquitous UI-framework on macOS.

This bug was trivial to exploit: Link with `AppKit` — arguably the most important framework on macOS — and listen in on your users. No entitlement required. [Here’s](https://github.com/0xbf00/pocs/tree/master/CVE-2018-4184) my PoC.

## Impact
As part of my Master’s Thesis, I was investigating how sandboxing was used in the Mac App Store (MAS) at the beginning of 2018. To answer this question, I collected all free apps from the German MAS, resulting in a dataset comprised of 7 603 real-world apps. By my own measurements, I had collected 25% of _all_ apps available on the store at that time. This dataset came in handy when figuring out how many apps were (inadvertently) affected by CVE-2018-4184:

* 356 apps had an entitlement granting them legitimate microphone access
* At least 6523 _additional_ apps (roughly 90% of all analysed apps) could access the microphone due to this bug
* There were 1014 apps that a) imported a function related to audio recording though b) did not possess entitlements granting them legitimate microphone access but c) could still access the microphone due to the vulnerability identified. Most likely, these apps simply linked with a framework that happened to offer audio functionality, even though it was never used. But maybe not?

In summary, at the start of 2018, the vast majority of applications – at least 94.2% of apps analysed – could access the microphone, even though only 4.87% of all applications had the required entitlement. This is not all that surprising, considering the importance of `AppKit`. Check out [this paper](https://svs.informatik.uni-hamburg.de/publications/2019/2019-11-Blochberger-State-of-the-Sandbox.pdf) for more information about the dataset used here and some cool statistics about the App Sandbox’s adoption. 

## Disclosure Timeline
This issue was resolved in 81 days.

March 12, 2018 — Initial report sent to Apple </br>
March 21, 2018 — Apple confirms vulnerability, plans to address it in an upcoming security update </br>
June 1, 2018 — [Patch released](https://support.apple.com/en-us/HT208849). The patch modified `SpeechRecognitionCore`’s sandbox snippet to check for the microphone entitlement. In recent versions of macOS, the sandbox snippet is completely empty.

Fun fact: The patch was only provided for macOS 10.13 and above. A fully patched 10.12 (which received security updates well into 2019) is still vulnerable.