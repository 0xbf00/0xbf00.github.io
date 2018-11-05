---
title: Demystifying iOS App Cracking
date: June 16, 2015
---

This article is not a guide on how to crack iOS applications. It merely tries to explain the techniques used to circumvent the iOS DRM system. I do not in any way condone piracy.

-------

iOS apps come in packages with the filename extension _.ipa_. These packages are just renamed zip archives, and can easily be unpacked using appropriate tools. The resulting directory tree  is of little interest to us here and has been documented elsewhere [\[1, ][1] [2\]][2].

For a cracker the most interesting file is the executable, which can be found by inspecting the ```Info.plist``` file, specifically be looking up the value for the ```CFBundleExecutable``` key. Today, most binaries contain code for multiple architectures. Such files are called _fat_ binaries, stemming from the fact that they contain code for multiple architectures like _ARMv7_, _ARMv7s_ and _ARM64_ (also known as _ARMv8_). On the Mac, the same concept is used, but the code inside such binaries typically targets Intel's 32- and 64-bit processors.

At runtime, the dynamic linker (almost always _dyld_) will examine the file, determine the best architecture to run, process all load commands and then proceeds to execute the chosen slice. More information on the file format - _MachO_ - and information on the various load commands can be found on Apple's website [[3]][3].

![Architecture selection at runtime](/assets/images/blackbox_decryption.svg)

Essentially, the OS kernel can be treated as a black box that automatically decrypts part of the supplied binary - The part that runs _best_ on the available hardware. In this case, ```posix_spawn``` was chosen to launch the process, but any other similar function will do. To simplify things, the figure ignores the fact that only the decrypted portion is present in memory after launch.

On iOS, all third-party code must be code-signed by a valid developer ID. The code signature is specified as a load command just after the MachO header, so each _slice_ - rather than the whole fat binary - has its own code signature. The signature is validated by the kernel, and apps with an invalid signature are killed immediately. On non-jailbroken devices, the integrity of the application bundle is ensured by the OS. On jailbroken devices, most of an apps' contents are allowed to change, since critical security features are gone. Still, a code signature must be present for code to run - however, in this case, a pseudo signatures like those produced by _jtool_ and _ldid_ suffice.

Popular cracking tools such as _Clutch_ [[4]][4] use an ugly workaround to crack as many slices of an iOS binary as possible:
Let's say an app contains code for all three architectures mentioned above. _Clutch_ is then going to patch the header of the executable three times, each time forcing the operating system to execute a different slice. Obviously this only works if the device can execute the slice, meaning that an iPhone 6 can be used to create cracks containing decrypted copies of all three architectures, whereas an iPhone 4S can only decrypt the _ARMv7_ portion.

Here is the process visualized. Again, the device in question is an iPhone 5.

![Clutch on iPhone 5](/assets/images/clutch.svg)

In this case, the original binary contains three slices for different architectures. Because we are on iPhone 5 which uses a _ARMv7s_ compatible CPU, normally only the corresponding slice would be executed. _Clutch_ abuses the fact that ARM processors are generally backwards compatible, meaning devices capable of running _ARMv7s_ code can also execute _ARMv7_ code. In total, _Clutch_ executes the app twice, once for each supported architecture. In order to force the operating system to execute a specific slice, all other slices are set to contain Intel code.

Each slice is dumped by first spawning the new process using ```posix_spawn``` in a suspended state. This is accomplished by using the Apple only flag ```POSIX_SPAWN_START_SUSPENDED```. No code by the application is ever executed, but the slice in question is automatically decrypted by the OS. Next, after aquiring the mach port for the spawned process using ```task_for_pid```, its memory is copied to disk. Lastly, headers are patched where necessary (for example the ```LC_ENCRYPTION_COMMAND``` needs to be updated to reflect the fact that the new binary is no longer encrypted) and the processing of the next slice begins. If you are interested in the implementation details, check out the source code [[4]][4].

Finally, the decrypted pieces are combined into a new binary. Because the iPhone 5 does not support _ARM64_, the output only contains two slices. Still, the binary runs on iPhone 6 - albeit possibly a tiny bit slower.

It is important for developers to understand how this process works. Although the public opinion is largely shaped by discussions about piracy, there are also legitimate uses for app cracking: Penetration testers looking for vulnerabilities in a clients' app or developers working on _reproducible builds_ [[5]][5]. There are profound implications for what I've written in here when we take into consideration _App Thinning_ and _Bitcode_.~~, which will be the topic of my next article! Stay tuned!~~

I am not going to get around to write an entire article on this topic, so here is the gist of it:

_App Thinning_ results in binaries that only contain one architecture, forcing crackers to use multiple devices to crack each individual slice and then manually combine them to create a version that runs on as many devices as possible. _Bitcode_ on the other hand could allow Apple to create personalized versions of apps, allowing them to trace accounts that distribute cracked versions of an app (fittingly referred to as _traitor tracing_).
If used, both technologies will hopefully reduce the impact of application cracking on the revenue of iOS developers.

---------

Changelog:

- June 17, 2015: Fixed date, changed title to better reflect the contents of this article.
- September 10, 2015: Added disclaimer, added section on impact of _App Thinning_ and _Bitcode_ in iOS 9
- November 1, 2018: Updated parts of the article.

[1]:https://en.wikipedia.org/wiki/.ipa_(file_extension)
[2]:https://www.theiphonewiki.com/wiki/IPA_File_Format
[3]:https://developer.apple.com/library/mac/documentation/DeveloperTools/Conceptual/MachORuntime/index.html
[4]:https://github.com/KJCracks/Clutch
[5]:https://github.com/WhisperSystems/Signal-iOS/issues/641