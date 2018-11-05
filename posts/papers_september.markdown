---
title: Papers - September 2015
date: September 10, 2015
---

I am starting a new series on this site, where I comment on papers I read in the last few weeks. I intend to publish these articles bimonthly!

[> __Lines of Malicious Code: Insights Into the Malicious Software Industry__ (2012)](https://www.iseclab.org/papers/beagle.pdf)

> Some interesting techniques but almost no usable results: Malware changes over time, but remains stable for large periods of time. Who would have thought that binary matching and diffing were hard and you trade off speed versus accuracy? The bottom line is: malware changes just as normal software does, adding approximately 100-300 LoC on average in each new version.

[> __Before We Knew It - An Empirical Study of Zero-Day Attacks In The Real World__ (2012)](https://users.ece.cmu.edu/~tdumitra/public_documents/bilge12_zero_day.pdf)

> The paper uses surprisingly simple tactics to achieve its result, which is the identification of 18 zero-day attacks - of which 11 were unknown at the time of publication - from more or less publicly available data (Symantec's WINE dataset).

> Some of the more interesting tidbits are these:

> - A 'typical zero-day attack' lasts 312 days on average
  - 10% of security patches have bugs of their own (Check out [\[1, ][1] [2\]][2] for recent examples)
  - The number of attacks increase 2 - 100 000 times after the public disclosure of vulnerabilites

[> __Twitter Games: How Successful Spammers Pick Targets__ (2012)](https://www.cs.indiana.edu/~minaxi/pubs/acsac12-vv.pdf)

> Spammers use Twitter with varying degree of success. Spam tacts evolve quickly and are hard to analyse automatically. Ratelimiting and, more generally, costs associated with the modern Twitter API result in studies that work on very small data sets and are thus not really representative. Since the article is a couple of years old, chances are the findings are irrelevant by now. Be sure to check out related works if you are interested in the topic.

[> __Vanity, Cracks and Malware - Insights into the Anti-Copy Protection Ecosystem__ (2012)](https://www.iseclab.org/papers/vanity_cracks_malware_ccs2012.pdf)

> Surprise! Cracks are used by criminals to spread malware! The original source - dubbed the _scene_ - is mostly fine and has mechanisms to deal with malicious or faulty uploads (which result in what's called a _NUKE_). Instead, the intermediate distribution steps such as OCH, BitTorrent or even Usenet, allow parties unrelated to the original warez groups to attach their own malicious software.

> - The authors could be the only people to ever purchase a [Letitbit](http://letitbit.net) premium account
  - _AVG free_ apparently was at some point a _state of the art_ AV
  - Authors speculate that they could have found _0-day malware_, because they found new samples.
  - Even though their AV reported 2/3 of all files to be infected, only 13.33% actually infected the host. This is what's called a _false positive_, and is most likely not because the malicious code did not manage to persist, as the authors seem to assume.

> The article highlights the need for users to be able to verify the integrity of a certain crack or keygen downloaded through untrusted channels. To this end, it might be useful for release groups to sign their releases. The exact infrastructure to support this endeavor could be as simple as using PGP.

[> __Dual EC: A Standardized Back Door__ (2015)](https://eprint.iacr.org/2015/767.pdf)

> Offers interesting views behind the scenes of the Dual EC standardization effort. Be sure to also check out Schneier's paper ["Surreptitiously Weakening Cryptographic Systems"](https://eprint.iacr.org/2015/097.pdf), as well as [Project Bullrun](https://projectbullrun.org/dual-ec/), the project's website containing lots of referenced documents.

[> __Visualizing signatures of human activity in cities across the globe__ (2015)](http://arxiv.org/pdf/1509.00459v1.pdf)

> What the hell is that font? Short and sweet paper, though it's [interactive web counterpart](http://www.manycities.org/) is much more exciting.

[1]: https://xuanwulab.github.io/2015/08/27/Poking-a-Hole-in-the-Patch/
[2]: http://blog.exodusintel.com/2015/08/13/stagefright-mission-accomplished/