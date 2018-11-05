---
title: Papers - January 2016
date: January 11, 2016
---

Second installment of the _Papers_ series. Be sure to read [the first one](/posts/papers_september.html) from a couple of months ago!

[> __The Limitations of Deep Learning in Adversarial Settings__ (2015)](http://arxiv.org/pdf/1511.07528v1.pdf)

> _Adversarial samples_ are samples produced in such way that they differ minimally from beneign samples. Even though humans still correctly classify them, a DNN fails and produces class labels controlled by the adversary. Well written, _understandable_ paper. Impressive.

[> __Mind your language(s): A discussion about languages and security__ (2014)](http://www.ieee-security.org/TC/SPW2014/papers/5103a140.PDF)

> LangSec is a hugely important part of InfoSec that does not currently receive the attention it deserves. Absence of type-checking, (implicit) casts and overloading all constitute possible security problems that need to be carefully addressed. The paper is full of interesting tidbits, quotes and rather amusing vulnerabilities (Try to _rm_ a file called _-rf_ for instance).

[> __Going Bright: Wiretapping without Weakening Communications Infrastructure__ (2013)](https://www.cs.columbia.edu/~smb/papers/GoingBright.pdf)

> "Taking advantage of [existing vulnerabilities] is far preferable to introducing new vulnerabilities into other applications or infrastructure [...]". Better, yes, but not _good_. [Also somewhat related.](http://www.reuters.com/article/us-cybersecurity-nsa-flaws-insight-idUSKCN0SV2XQ20151107)

[> __ret2dir: Rethinking Kernel Isolation__ (2014)](https://www.usenix.org/system/files/conference/usenixsecurity14/sec14-paper-kemerlis.pdf)

> Interesting, practical paper doing useful research. The authors, which were also nominated for a [Pwnie](http://pwnies.com/nominations/), also released all source code.

[> __ROPecker: A Generic and Practical Approach for Defending Against ROP Attacks__ (2014)](http://www.mysmu.edu/phdis2008/yqcheng.2008/ROPecker-NDSS14.pdf)

> Cool research on ROP attack mitigations. Does not modify the binary - neither on disk or at runtime - and is thus much more suited to general application. Unfortunately only protects user-space code and there are a few ways to bypass the techniques. Fortunately, these techniques greatly increase the cost of an adversary, reducing the likelyhood you will fall victim to an attack.

[> __Protecting Android Apps Against Reverse Engineering by the Use of the Native Code__ (2015)](#TODO#)

> The authors propose techniques to raise efforts needed to reverse engineer Android applications by introducing _one_ native function responsible for field accesses, method call indirection and opaque predicates. Not a huge fan, considering the performance (and therefore _battery_) impact is on the order of 10x to 30x.

Also worth reading:

- [__The Underground Economy of Spam: A Botmaster’s Perspective of Coordinating Large-Scale Spam Campaigns__ (2011)](https://www.iseclab.org/papers/cutwail-LEET11.pdf)
- [__A Computational Approach for Obstruction-Free Photography__ (2015)](https://people.csail.mit.edu/mrub/papers/ObstructionFreePhotograpy_SIGGRAPH2015.pdf)