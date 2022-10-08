# Core ideas
 - The more dictionaries you have, the more accurate you get.
   - Official dictionary data is carefully and manually checked for many times. (「舟を編む」の中で、「『大辞林』を作るのに28年かかった」と言っていた). However there are lots of errors introduced by program when parsing into yomichan or other popular dictionary format. So the idea is that with multiple dictionaries you can somehow fix some of these errors either automatically or by yourself based on contents.
   - There are lots of word frequency lists in the wild. Each of them covers different sets of vocabulary and is generated using various corpus. The more frequency lists you gather, the closer you can get to the real frequency distribution.
 - Storage cost is less important than speed.
   - In the modern era, people have devices equipped with hundreds of GB. One has been used to an app taking up to GBs of storage but cannot tolerate half a second of delay for an app to do reaction.
 - A Japanese word can be indexed uniquely by its reading and writing form.
   - Japanese language is complicated due to its writing system. There are too many 同音異義語 and 同形異音語. Besides that there are also 振り仮名 and 送り仮名 which made the language even more complicated. After the publishing of 現代仮名遣い and 常用漢字表, things are getting better but it's still too complicated to define a Japanese word precisely without context. So basically for convenience we consider two words with the same reading (only modern kana, not including pitch accent nor the は/わ stuff) and writing as one word, while ignoring the actual meaning and usage cases.
   - Which means, `(する, する)` and `(為る, する)` and `(爲る, する)` and `(擦る, する)` are all different words. In majority of dictionaries, する is referred as 擦る, but there are still some dictionaries (and in many word frequency lists) who consider する the same as 為る. How to handle this obscurity will be discussed further in the Database section. And how to handle 為る and 爲る will be discussed when we introducing Kanji variants.
   - The pro of this is that we can merge explanations from different dictionaries into one word. And also we can define the word frequency more precisely and sort the searching results according to frequency!
   - However due to the fact that some terms are lack of reading in the yomichan data and some terms have troublesome format which cannot be parsed correctly by program, we have to discard some data when processing these dictionaries. But luckily with the help of other dictionaries we can get some of them back into our database.
 - AOT (ahead-of-time) building database is better than import-and-build.
   - Importing the dictionary files usually happens only once. People do not tend to try importing or deleting dictionaries on their phones frequently. So why not build the database once for all?
   - The main purpose of this project is a personal substitute of those Japanese dictionary apps and can be tailored according to my own interest. So at the beginning the database was built across my own collections of yomichan dictionaries. However some of my friends (both domestic and foreign) grew more and more interests on it so I decided to include more dictionaries and remove bilingual ones except JMdict. But still I want keep the database building process on my own computer without porting the python code to dart. However one can build his/her own database easily using `databse_build/jisho.ipynb`.
   - Using python to process the dictionary data is way much easier than writing portable code using dart. Firstly, I'm not familiar with dart nor flutter. I choose it only because it's easy to write portable apps which can be installed on both Android and iOS (although I myself don't have any apple device thus building ipa becomes a problem for me). Secondly, AOT allows me to do mass computations and consume as much memory as I want. Also it's far more convenient to debug and adjust the empirical parameters in real time when processing data.
   - Sqlite is a very portable sql databse format and can be included in many other apps. In case anyone wanted to build their own dictionary apps or would like to process these data programmingly, he/she can extract the database from the app without much effort. Also the performance of sqlite is highly optimized even on mobile platform, so incremental search becomes possible. One of the most useful feature for me, searching word by REGEXP, can also be done thanks to the sqlite (as the time of writing, REGEXP search is not supported on iOS).
   - The most important reason is that building database when all dictionary data are given at once (and even with the result of last successful build) can greatly help us to gain more information and do safe decisions. E.g. some word freq list does not have readings in it, however the frequency of a word can vary greatly according to its reading. Like the word 大勢 is usually read as おおぜい, however it can also be read as たいせい or even たいぜい in some cases. It's unreasonable to attribute all frequency data evenly on these three readings. However with the help of other freq lists which has readings appended for these three words, we can distribute the frequency into 3 parts considering weights obtained from these data. The detail of this process is actually little bit more complicated and will be discussed in the Database section.
 - Keep it as simple as a Japanese dictionary app should be.
   - Arujisho is designed to be a Japanese dictionary app and only a Japanese dictionary app. Keep it simple without adding functions that are unrelated to Japanese. So we currently tend not to support making it a video player, a browser, or a book reader etc. However, any idea about Japanese NLP that is suitable for a dictionary app is welcoming.
   - Less on UI, more on database. Flutter 苦手だから, I would rather put more focus on the backend stuff. Although this project welcomes contribution, 多分 nobody will issue a pull request だろう（笑）

# Database
This section will only describe basic ideas and features. For detailed algorithm one can read the `database_build/jisho.ipynb` file.
## Word Weight
In order to sort the searching result reasonably, we need to assign a weight to every word. One might think the easiest way is to use a word frequency list. However there are lots of word frequency lists covering different words. Also some dictionaries themselves have weight data for their terms. The most trivial way is to sum them all up, but here exists several problems:
- The data in word frequency list are mostly rank-based, which means you only have the ranking of a word (the smaller the better). However the weight from the dictionary is actual weights data (the larger the better).
- Data have different scales. E.g. if two words are weighted `(100000, 120000)` in one dictionary, in another dictionary they are `(2.4, 1.3)` correspondingly, then the weight data from the second dictionary is almost useless if they are simply added.
- Different word frequency use different corpus and different processing methods. If we deem the word freq list as a sample from the real word freq distribution, the confidence intervals of different samples is different. E.g. BCCWJ is made by NINJAL and is balanced between different type of usage scenarios and is also checked manually. However some freq lists are generated by a very narrow field of resources and might contain error when processing. It's unreasonable to simply add them up.
- Some word frequency list do not contain word reading. One cannot distinguish the difference of freq between different readings of a word. It's irresponsible to just add the frequency weight to all of these readings.
- Some word frequency list have outlier data due to parsing error that would greatly affect the correctness of result. E.g. a word that is very rare and should be weighted about 1 or 2 but instead turns to be 1000000 in a certain list. If we sum the weight up directly, it will get averaged and goes to a really high position where we would not want it to be.
- Most words do not show up in word frequency list. E.g. the word freq lists actually have only about 200k words if intersected with the dictionary vocabulary. However those dictionaries add up to more than 800k words. So how to sort these unweighted words?

In the following subchapters we will discuss exact measures taken to deal with word weight.
### Transform word ranking back into Zipf-Mandelbrot distribution
In order to sum up word frequency data reasonably, we deem every word freq list as a sample from the real frequency distribution. And the confidence of the source is corresponded to the size of the sample corpus (so we can multiply the weight directly).

We first transform the word freq rank data back into word freq distribution using Zipf-Mandelbrot distribution (which is a enhance version of the original Zipf distribution). Zipf distribution is a formula to describe the distribution of word frequency vs frequency ranking. And the original version has several problems, one of which is that the parameters will also change according to the size of corpus, thus it's not consistent between different sizes of corpus. The parameters of Zipf-Mandelbrot is fitted to CC-100 word frequency list tokenized by me using CC-100 monolingual dataset which is a very large web corpus filtered from CommonCrawl dataset using LM perplexity as criterion to reach high quality.

### Adjust weight of word frequency
There are two kinds of weights in this system. The word freq list itself is assigned a weight (called `lweight` in code) according to manual assessment of the vocabulary size, confidence of source, quality of data and personal favor. Another weight is slightly adjusted within the list according to the word. More specifically, if the word is pure kana, then its weight is slightly lowered because many lists do not do normalization when tokenizing, which makes those Kanji words written in kana become kana word. If the word does not have reading in word freq list, we will search the dictionaries to for all possible readings. If it has only one reading, the reading will be added to it. Otherwise the weight of this word will be also lowered.
### Combine frequencies robustly
After we get these weights from word lists, we can add them up in a robust way to decrease the influence of any possible outlier data. We used a mix of weighted version of Hodges-Lehmann median and weighted average to gain robustness without sacrificing useful data.
### Dealing dictionary weights
Now we've finished the weight generated from word freq lists. However we need to deal with the weights data in dictionaries. After a manual analysis of dictionaries with weights data, we find that they are usually inconsistent, in other words, they are more like a relative value used to sort a certain search result. Also there are negative weights in some dictionaries. Instead of doing normalization on all dictionaries, we decided to respect these negative values (they usually mean that this word should not be written or read in that way). So we add a certain universal weight to all dictionaries to make it positive.

Because there are lots of words who do not have any weights yet. We take two measures in order to sort more precisely:
- A word is added with additional weight if it's recorded by more than one dictionary. The more dictionary it's in, the more additional weight it will get.
- A word is added with another additional weight according to the length of its meaning. The longer the description is, the more weight it gets. Note that monolingual and bilingual dictionary have slightly different parameters because the average entropy of different languages is different.

The weights added are irrational numbers in order to minimize collisions.
### Add all up
Finally we can add those weights together. However there is one more thing to deal with, which is the weight of a word that has multiple readings. To make it simple we distributed the weight onto these readings proportionally with the weights from last version of dictionary database. After processing the database several times, the ratio will converge into the expected value.
## Word processing
### Reading
Reading is parsed and transformed into 平仮名 (even カタカナ word, but keep `ー` untouched). The reason is that I personally cannot read カタカナ very well. But recently I find it might not be a good decision, so this behavior might be changed in the future.
### Written Form
Words are slightly filtered and formatted. Besides that, all pure latin words (exclude spaces) are replaced by its カタカナ reading. That's because the searching frontend will treat latin letters as romaji in early version of this app, and we think English words are not Japanese if not written in カタカナ.
### Fixing
We found that in several dictionaries some words are incorrectly separated and some words are not incorrectly not separated due to format parsing issue as the separator used is '・'. E.g.「五・一六軍事クーデター」 is separated and 「五」 is pronounced as 「ゴイチロククンジクーデター」. Also 「5」 can be read as 「ピーエムにてんご」 due to 「PM2・5」. We choose 「デジタル大辞泉」 as a reference to fix these errors because the separator it used is 「／」.
### Dangling
There are some entries with an empty reading field. Here we call them dangling entries. After parsing all dictionaries data for the first time, we check all these dangling entries if they have multiple readings. If the word exists in other dictionaries and have only one reading, the reading will be added to is and the dangling entry will be fixed. If the entry is just a single Kanji character, it will be added to all possible readings.
### Merging
A Japanese word could have several written forms. Some dictionaries will include some of them, while others might include another part of them. To merge these different words together, we checked all possible readings that have more than two written forms. Among these written forms, if there exists a pair that the intersection of its dictionaries is not empty and the content of description is exact the same, we can safely deduce that this pair of words are just different writings of a same word. Thus we merge these terms together, copying all meaning of one into another, and choose a term with higher weight as the main term. E.g. the word `いかが` is merged with `如何`, and in the app it will be shown as `いかが ➡〔如何〕`.

Besides, we also do merge if a reading have only two written form, and one of which is written pure kana. E.g. 「日常風景」 is merged into 「にちじょうふうけい」. Also for convenience we do one-way merge (only merge the meaning of 漢字 word into 仮名 word) for some common expressions such as `(など, 等)` and `(について, に就いて)`.

## Kanji variants
Chinese characters (or CJK characters) may have many variants. Sometimes they look (almost) exactly the same but has different encodings. E.g. 「奬」「獎」「奨」 are different variants of a same character. Japanese have 新字体 and 常用漢字表, but lots of 拡張新字体, 表外字, 舊字體, 略字, 俗字 etc. are used in the wild. In order to unify these variants, we parsed the Unihan variants data from official Unicode project, variants data from OpenCC Chinese Conversion project, and shinjitai data from official documents issued by Japanese governments, used disjoint set to unify them all, and filtered out several unreasonable variants pairs.

To determine the importance of a kanji, we combined our dictionary data as well as kanji-frequency lists by scriptin. Based on the importance data, we  could convert all kanji variants groups into single characters which have the highest importance in that variant group (except top 1500 kanji used in Japanese). The original form is recorded in database in `origForm` field.
## Format

### Dictionary folder structure
TODO
### Database format
TODO

# Frontend
TODO
