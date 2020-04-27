---
title: Exploring Sandbox Coverage on macOS
date: April 27, 2020
---

> **Note**: This article describes my approach to _analyse the quality of sandbox profiles on macOS_. This is an important topic, as the sandbox is the core technology making sure apps and programs do only what they are supposed to do. There are a number of limitations and problems with my approach. This article is therefore not about the concrete results I got, but instead about how to approach this problem and what I've learned so far.

The _principle of least privilege_ [states](https://dl.acm.org/doi/10.1145/361011.361067) that programs should operate with the least amount of privilege necessary to complete their task. Sandboxes are supposed to implement this principle, though it is often unclear how effectively they do their jobs. This article deals with this topic.

App Sandboxing on macOS is configured using _entitlements_. There are only relatively few coarse-grained entitlements, but thousands of different apps. Each app has its own unique resource requirements. Because the abstract base profile underlying the App Sandbox encapsulates _all_ permissible behaviour for all apps, it cannot perfectly fit each _individual_ app. As such, it is to be expected that there are rules unused by some apps, but that are used by others. Accepting this limitation means that individual profiles are bound to be overprivileged: there is always wiggle room for apps to perform actions they were not intended to perform. This is the reality inherent in any sandboxing solution: there’s always a tradeoff between ease-of-use and flexibility.

Another question remains: Are there completely unused rules in the abstract base profile? These rules are included in every application’s sandbox profile and therefore deserve special attention: They could be either _redundant_ or _overly permissive_ and can be removed in both cases, reducing complexity without breaking valid functionality.

![Overview: The abstract base profile underlies all application sandboxing profiles](/assets/images/sandbox_coverage/coverage_motivation.svg)

On macOS, the App Sandbox’s ruleset is a whitelist of allowed functionality. Unused, non-redundant sandbox rules could pose security risks if they allow resource accesses that are not needed at runtime.

Note: sandbox profiles with no unused rules are not automatically _appropriate_. For instance, the profile consisting of just the single rule `(allow default)` is not a sensible sandbox configuration, even though it contains no unused rules.

## Approach
Knowing which rules are _not used_ requires knowing which ones _are used_. We are interested in something akin to code coverage, albeit for sandbox profiles. Let’s be pragmatic and call it _sandbox coverage_.

Here’s what I did to approach the problem:

1. **Turn on sandbox logging for all rules**</br>
`Sandbox.kext` logs its decisions to the syslog. I tried to match these logs back to the rules that generated them. Logging is not enabled for all rules by default.
2. **Collect sandbox traces (log entries)**</br>
Sandbox logs are only generated at runtime. To collect them, we need to _run_ and thoroughly _test_ apps to reach as much programmed functionality as possible.
3. **Match sandbox traces to sandbox rules**</br>
I built a matcher to figure out _which sandbox rule_ was responsible for _which log entry_.
4. **Generalise matches to abstract base profile**</br>
Results from the previous step are tied to a concrete sandboxing profile. We are mainly interested in which rules from the underlying abstract `application.sb` profile are not used. In this step, we generalise our results using simple heuristics.

### Sandbox Logs

Apple’s sandbox logs its decisions to the system log. Each log entry consists of the decision taken (`allow` or `deny`), the affected sandbox operation name and a string describing the resource accessed. Open up `Console.app`, wait a few seconds and you will see examples such as

```
Sandbox: systemsoundserve(252) deny(1) file-read-data /Library/Preferences/Logging/com.apple.diagnosticd.filter.plist
```

By default only `deny` decisions are logged.  `allow` decisions are however much more interesting because the App Sandbox uses a whitelisting approach. To **enable comprehensive sandbox logging**, we can use [`simbple`](https://github.com/0xbf00/simbple) to add the `report` modifier to all `allow` rules. Modified profiles will look as follows

```sh
# The --patch flag adds report modifiers to all allow rules
$ ./simbple ~/Library/Containers/com.apple.calculator/Container.plist --patch | tail -n 9
(allow
    mach-lookup
    (global-name "com.apple.mobile.keybagd.xpc")
    (with report)) # Modifier added by simbple
(allow
    mach-lookup
    (global-name "com.apple.backgroundtaskmanagementagent")
    (with report)) # Added by simbple
```

To **collect sandbox traces / log entries**, all that is left to do is running the target program with the modified sandbox profile. To do this, simply compile the new sandbox profile and inject it into the app’s `Container.plist` file. How _complete_ your results are depends on your testing methodology. Ideally, you’d want to exhaustively test apps and trigger all functionality. This might be feasible when you are dealing with only few simple apps, but does not scale at all. Products such as [Squish](https://www.froglogic.com/squish/) can script GUIs on macOS, but they are geared towards developers with source code access and break down quickly when used on third-party code. I ended up simply opening apps and letting them run idly for sixty seconds. In addition, I tested a small set of apps more thoroughly to see how results would look like with a more comprehensive testing strategy.

Sandbox logs after parsing and cleanup look like this:
```json
{
    "action": "allow",
    "argument": "/System/Library/Frameworks/GSS.framework/Versions/A/GSS",
    "operation": "file-read-metadata"
},
{
    "action": "allow",
    "argument": "/Applications/Calculator.app",
    "operation": "file-read-data"
},
```


### Rule Matching

The general order of evaluation for sandbox profiles is from beginning to end. Later rules _can_ modify earlier ones, but don’t always (there are rules here but they don’t matter for this discussion). Earlier rules **never** modify later ones. When you remove the last rule in a sandbox profile, a sandbox exception might be removed (last rule was a `deny` rule)  or added (last rule was an `allow` rule).

![Overview: Matching Architecture](/assets/images/sandbox_coverage/rule_matching.svg)

Using this knowledge, we can build a _sandbox oracle_ to figure out _which rule was responsible for a given sandbox decision_: given a decision from the sandbox logs and the corresponding sandbox profile, we repeatedly remove the last rule from the profile and check if the sandbox would decide differently. Once it does, we know that the last removed rule is responsible for the original decision.

Let’s consider the following example. According to the log entry, the sandbox allowed the program to read `a.dylib`. Looking at the example ruleset, it should be clear that the `device-microphone` rule has nothing to do with our log entry, hence nothing changes when removing this rule. Once we remove the next rule however, only the `(deny default)` rule will remain. Given this profile, the sandbox will _deny_ the request. At this point, we know that the second rule is responsible for the log entry.

![Example for matching](/assets/images/sandbox_coverage/matcher_example.svg)

The basis of the sandbox oracle is `sandbox_check`, a pretty much undocumented function. Trying to work around some of its limitations, I wrote functionality that would actually trigger sandbox checks to see what is allowed and what’s not. Check out [the code](https://github.com/0xbf00/macos-sandbox-coverage) for more infos.

### Generalising results

Starting out, we were interested in which rules of the _abstract_ base profile (`application.sb`) are unused. Up until now however, our results are tied to the _specific_ application sandboxing profile.

We can generalise our results by mapping them onto (a generic instantiation of) the `application.sb` profile:

![Overview: Generalising Sandbox Profiles](/assets/images/sandbox_coverage/profile_matching.svg)

To do this, we first craft a generic container metadata file where all sandbox parameters are set to generic placeholder values, all non-essential sandbox snippets are removed and only the `com.apple.security.app-sandbox` entitlement is specified (**1**). We then use [`simbple`](https://github.com/0xbf00/simbple) to generate the corresponding generic sandbox profile (**2**).

 The application’s sandbox profile (**3**) is used during matching. To generalise the results, we compute a normalised application sandboxing profile (**5**) by “normalising” the app’s `Container.plist` file (**4**). In contrast to (**1**), we leave entitlements and sandbox snippets as they are.

We then create a mapping between the application’s sandbox profile and its normalised version (**6**). This can be done rather easily, because the order of rules is identical in both. Finally, we create a second mapping between the normalised version and the generic sandbox profile (**7**), which is possible because both use the same generic placeholder values. This mapping is not 1:1, because sandbox snippets are missing from the generic profile.

With these mappings, we can now transfer our matching result from the application sandbox profile to the generic sandbox profile. 

## Results
I ran the sandbox coverage analysis on 6 703 free apps from the Mac App Store. Each app was opened, left running for 60 seconds and was then closed again. In total, I collected just shy of 17 million sandbox log statements. Of these, a little over 4% of logs yielded inconsistent results (sandbox decision during matching differs from original) and could not be matched. There are a number of reasons for why this was happening. See the next section for a discussion of the problems of this approach.

In my automated tests, sandbox coverage for individual apps never exceeded 14.5%. Apps I _manually interacted with_ had slightly higher coverage at roughly 16%. Nevertheless, in my work, I could only find proof that roughly one out of five sandbox rules was actually used at runtime. Even if we assume that errors in the project mean only 50% of rules were captured or could be matched, that still means that the majority of sandbox rules are not needed and the resulting sandboxing profiles are needlessly complicated.

Though the strategy to get logs for individual apps was very basic, generalising and combining all results yielded higher sandbox coverage statistics for the abstract base profile. Here, 28% of all rules are used. Again, the majority of rules appear _not to be used by any app_. To visualise the results, you could for instance colour every rule that was used in green:

![Example Visualisation of Sandbox Coverage](/assets/images/sandbox_coverage/coverage_visualisation.png)

Knowing what parts of a sandboxing profile are actually used is very helpful. For instance, it allows you to harden your own machine!

## Problems and Limitations
If you’ve read this far, you might have already thought of some issues with my approach. Let me know [on Twitter](https://twitter.com/0xdead10cc) if you have anything to add to this list:

* **TOCTTOU (Time of check to time of use)**: As rule matching is performed _post facto_, the system state underlying a particular decision could have already changed when we get around to matching. We can detect _inconsistent_ matches, where the decision the matcher returns differs from the original decision. It is however also possible that a _different rule_ produces the same decision during matching, making it impossible to guarantee correctness of matches.
* **Incompleteness of dynamic analysis**: Dynamic analysis is incomplete by definition; there are always code paths your testing will not hit. Furthermore, existing tools to automatically test apps are geared towards developers with source code access and cannot be used on random third-party apps.
* **Incomplete sandbox logs**: Some sandbox operations don’t produce logging output (e.g. `device-microphone`), even when explicitly instructed to. For other operations, only some of the parameters influencing the sandbox decision are logged (e.g. only the filename, not any flags).
* **Impractical APIs to query sandboxing**: `sandbox_check`  was not designed for what I am using it for here. Some of its limitations I could work around, some I could not.
* **Incomplete dataset**: There is no single repository of every Mac app in existence. In my work, I looked at free apps only. Paid apps might behave differently, although I would bet against it.

These limitations are pretty fundamental. They are unfortunately inherent in any approach that tries to perform matching _post facto_ in _user space_.

## Next steps: Move matching to the kernel
I think it is possible to solve most limitations by performing the matching in the kernel at the time the sandbox makes its decision. As you know, sandboxing is implemented in a kernel extension (`Sandbox.kext`). This kernel extension implements a policy module that is called upon by the mandatory access control framework embedded in XNU. The center piece of this framework is the `MAC_CHECK` macro, defined in [security/mac_internal.h](https://opensource.apple.com/source/xnu/xnu-6153.11.26/security/mac_internal.h.auto.html):

```c
/*
 * MAC_CHECK performs the designated check by walking the policy
 * module list and checking with each as to how it feels about the
 * request.  Note that it returns its value via 'error' in the scope
 * of the caller.
 */
#define MAC_CHECK(check, args...) do {                                  \
	struct mac_policy_conf *mpc;                                    \
	u_int i;                                                        \
// ...
```

It should be possible to replicate the matching logic inside of this macro. Here we would repeatedly query `Sandbox.kext` for its decision while changing out a processes’ sandbox profile underneath the kernel extension.

For this to work, we would need

1. A primitive to change out the installed sandbox profile for a process. Since we are working in kernel space, it should be possible to simply mess with `Sandbox.kext`’s memory directly.
2. A syscall for a user space process to send a list of `n` compiled sandbox profiles to the kernel, where `n` is the number of rules in the complete profile. The kernel would install the complete profile to start and use the rest in the modified `MAC_CHECK` macro, similarly to how matching works in user space.
3. A method for the kernel to transmit results back to user space