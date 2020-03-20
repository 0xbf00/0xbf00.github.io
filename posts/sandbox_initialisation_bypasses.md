---
title: "The Long And Winding Road To Safety: Three Ways to Bypass Sandbox Initialisation on macOS"
date: March 18, 2020
---

From [my first post](/posts/sandbox_tour.html) about sandboxing on macOS:

> All programs are initially launched _non-sandboxed_. This little-known fact, which is completely absent from all official documentation, is the achilles heel of the whole system. Under _normal_ circumstances, the sandbox is initialised before transfer is controlled to application code. However, because initialisation happens in the context of the application itself, there is precious little room for error. As it stands, there is no process to ensure applications, whose metadata suggest they should run sandboxed, actually run sandboxed.

![Overview of App Sandbox Initialisation Bypasses](/assets/images/sandbox/initialisation_bypasses_overview.svg)

In my opinion, application sandboxing on macOS should offer _declarative_ security. If an application or binary is properly code-signed and contains entitlements suggesting it runs sandboxed, there should be no way for that app or binary to run unsandboxed. After all, the case for application sandboxing to _contain potentially malicious apps_ is much stronger than is the case for sandboxing to _guard against exploits targeting third-party apps_ (are there any such documented cases?).

Currently though, the App Sandbox does not offer declarative security. In today’s post, I will show you three different ways for malicious developers to bypass sandbox initialisation. The graphic above gives you an idea about the structure of this post. Let’s get started.

## No `dyld`, No Sandbox
`dyld`, macOS’s dynamic linker, starts the process of sandboxing an app. It does this by calling the initialiser for `libSystem`, which in turn [calls on `libsystem_secinit.dylib`](https://opensource.apple.com/source/Libsystem/Libsystem-1281/init.c.auto.html). If your program does not use `dyld` -- in other words, is statically linked -- this code is never called. Sandboxing will never be activated, irrespective of the entitlements of the program.

The kernel source code responsible for loading Mach-O programs is located in `parse_machfile` in `bsd/kern/mach_loader.c`. If a binary contains neither  `LC_MAIN` nor `LC_LOAD_DYLINKER` load commands, its entry point will be called directly, without going through `dyld`.

Creating [the PoC](https://github.com/0xbf00/pocs/tree/master/no-dyld-no-sandbox) took me longer than I’d initially thought. As far as I know, standard tools on macOS do not support creating statically linked programs. In the end, I made some changes to [`minmacho`](https://github.com/stek29/minmacho) to produce the proof of concept. [The resulting program](https://github.com/0xbf00/pocs/tree/master/no-dyld-no-sandbox) is incredibly simple and does nothing but spin in a tight loop. It is properly code signed with the sandboxing entitlement but does not run sandboxed.

```bash
$ asctl sandbox check --pid 23811
/Users/jakob/Programming/minmacho/a.out:
	signed with App Sandbox entitlements
	running without App Sandbox enabled
	running unsandboxed
```

## Nothing to See Here: `dyld` Interposing Strikes Again
Let’s assume for the moment that we are dealing with a dynamically-linked program. In this case, `dyld` gets called to load the target program. Towards the end, it will initialise all loaded libraries, starting with `libSystem`. `libSystem` in turn [calls on](https://opensource.apple.com/source/Libsystem/Libsystem-1281/init.c.auto.html)  `libsystem_secinit.dylib` to initialise sandboxing.

This library first extracts and decodes the host programs’ entitlements. Reverse-engineering `libsystem_secinit.dylib`, you’ll find the library [uses the following logic](https://github.com/0xbf00/libsecinit/blob/24962765158a9e0330f2e8732a4738b5c888d2c9/src/libsecinit.c#L142) for this purpose:

```
xpc_object_t entitlements = xpc_copy_entitlements_for_pid(getpid());

if (entitlements) {
    const void* data = xpc_data_get_bytes_ptr(entitlements);
    size_t len = xpc_data_get_length(entitlements);

    ctx->entitlements = xpc_create_from_plist(data, len);
    xpc_release(entitlements);
}
```

Here you can see the library uses `xpc_copy_entitlements_for_pid` to get the program’s raw entitlements. For apps without entitlements, this function returns `NULL` and the sandboxing process exits. It is trivial to make this function return `NULL` _even for programs with entitlements_.

Back in 2012, [axelexic](https://github.com/axelexic) used `dyld` interposing -- a technique to replace functions at runtime -- to bypass sandbox initialisation. The technique is possible because `dyld` a) runs in the application's context and b) processes interposing _before_ initialising loaded libraries. Hence, when `libsystem_secinit.dylib` is finally invoked, functions it depends on might have already been changed out from under it. The PoC published [here](https://github.com/axelexic/SanboxInterposed) does exactly that. It uses `DYLD_INSERT_LIBRARIES` to inject a dynamic library that neuters `__mac_syscall`. In the years since, Apple changed `dyld` to ignore environment variables for apps with _useful_ entitlements such as the microphone entitlement. In addition, `dyld` environment variables are ignored for apps launched from the system's `/Applications` folder (which is `/System/Applications/` in macOS Catalina).

These restrictions don't apply if you simply _link_ with the interposing library, which also enables bypassing the App Sandbox. Wondering whether this is expected behaviour, I sent [a PoC](https://github.com/0xbf00/pocs/tree/master/CVE-2020-3854) to Apple in September 2018. One and a half years later, this January, a fix for [CVE-2020-3854](https://support.apple.com/HT210919) was released. So, what’s changed? As far as I can tell, nothing. [The PoC](https://github.com/0xbf00/pocs/tree/master/CVE-2020-3854) still works. I am not terribly surprised about this. Interposing is a very old _feature_. Changing it might break existing applications and therefore carries a risk. In addition, Apple said they added checks to make sure MAS apps are not affected. My only gripe is why the issue is included in release notes of macOS 10.15.3 if nothing changed.

## Trouble in Decoding Land: What _Are_ Entitlements?
Third scenario: we are dealing with a dynamically-linked, code-signed program with entitlements. The program doesn’t actively mess with sandbox initialisation in ways we discussed in the previous section. What else can go wrong?

Let’s look at the snippet from above again:

```
xpc_object_t entitlements = xpc_copy_entitlements_for_pid(getpid());

if (entitlements) {
    const void* data = xpc_data_get_bytes_ptr(entitlements);
    size_t len = xpc_data_get_length(entitlements);

    ctx->entitlements = xpc_create_from_plist(data, len);
    xpc_release(entitlements);
}
```

Now, `xpc_copy_entitlements_for_pid` will succeed and return a non-`NULL` XPC data blob. Next, `xpc_create_from_plist` parses the data and creates a dictionary for further processing. Can _this_ function fail when given _valid_ entitlements data? It surely can.

First though, what _are valid entitlements_? Is it legal to embed any valid plist as entitlements in a program? Only a subset of all valid plists? You’ll notice that the kernel calls out to `mac_vnode_check_signature` and kills your program if you use completely random keys in entitlements. As long as your keys use the `com.apple.security.` prefix though, you are good. What about the entitlements’ encoding? Plist files can use a variety of encodings: binary, JSON, UTF-8, UTF-16, UTF-32, …. Is it legal to use any of these encodings for entitlements?

To the best of my knowledge, there are no definitive answers to these basic questions. In practise, every tool handles the situation differently. It's a mess: Xcode enforces UTF-8 encoding, `codesign` works with almost anything you throw at it, `asctl` seems to handle all valid plists, [\@patrickwardle](https://twitter.com/patrickwardle)’s `WhatsYourSign.app` [assumes UTF-8 encoding](https://github.com/objective-see/WhatsYourSign/blob/e0e3a05902192687c74382b2eebc24647fedfbf6/WhatsYourSignExt/FinderSync/Signing.m#L747). Crucially, the function in question above — `xpc_create_from_plist` — uses _its very own, separate_ plist parser.

In 2018, I noticed that sandbox initialisation failed for programs with UTF-8 encoded entitlements that included [an optional BOM](https://stackoverflow.com/questions/4614378/getting-%C3%AF-at-the-beginning-of-my-xml-file-after-save?rq=1) ([PoC here](https://github.com/0xbf00/pocs/tree/master/CVE-2018-4229)). At the time, `xpc_create_from_plist` would fail and return `NULL`, thereby short-circuiting sandbox initialisation. There are actually apps on the MAS ([1](https://itunes.apple.com/us/app/bridge-constructor-free/id579589796?mt=12), [2](https://itunes.apple.com/us/app/rock-run/id620099316?mt=12]), [3](https://itunes.apple.com/us/app/goldman-hd/id606805906?mt=12)) that triggered the issue. Because they passed App Review, I think it is fair to assume that nobody at the time verified applications were _actually running sandboxed_. Apple assigned CVE-2018-4229 and fixed this particular problem for [macOS 10.13.5 and up](https://support.apple.com/en-us/HT208849). The general problem persists: entitlements that cannot be decoded are silently ignored. Try it out for yourself: Use UTF-[16 | 32] encoded entitlements and sandboxing will be disabled. Throw a simple fuzzer at this function and you’ll likely drown in issues.

## Takeaway
The lesson of this article: Don’t **ever** trust the entitlements of programs you run. Malicious developers can craft apps that look and smell like they are sandboxed (and therefore might seem _“safe”_ to run) but aren’t. It’s also possible for offending apps to use whatever sandbox profile they want. How about `(allow default)`? You’d never know; there are no tools for users (or the App Review team) to check for misbehaving apps. The best you can do is use `asctl` or `Activity Monitor.app`, neither of which will tell you _what_ an app’s sandbox profile is or what it does.

## Outlook
I don’t have special insights into the development process at Apple and the challenges they are facing. I’m sure there are reasons for why things are the way they are. Still, here’s what I think needs to change for the App Sandbox to be truly useful:

1. Do not allow user code to execute prior to initialising the sandbox. I think this could be achieved in one of two ways: ban `dyld` interposing outright for code with entitlements or map _all_ user code as not executable initially. Only _after_ running `libSystem`’s initialiser set the code pages to be executable.
2. Do not fail gracefully: if a program contains entitlements that cannot be decoded, kill the program. Better safe than sorry.
3. Do not allow statically-linked binaries or finally move application sandboxing to the kernel (don’t blame me for kernel bugs that may occur as a result of doing so!). Note that `Sandbox.kext` already enforces the platform sandbox profile on all apps.

## Changelog

March 20, 2020:

* Corrected statements regarding `dyld` environment variables (h/t [\@lapcatsoftware](https://twitter.com/lapcatsoftware))
* Added note about platform sandbox profile to Outlook (thanks [\@sdotknight](https://twitter.com/sdotknight))
* Clarified how I think App Sandboxing should ideally work (cc [\@s1guza](https://twitter.com/s1guza))
* Added explicit mention of CVE-2018-4229 to text (thanks Max!)