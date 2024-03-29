<h1><img align="left" src="icon.png" width="48px">ある辞書</h1>

[![Codemagic build status](https://api.codemagic.io/apps/62d0c7c9b2128b2e5dbb1002/default-workflow/status_badge.svg)](https://codemagic.io/apps/62d0c7c9b2128b2e5dbb1002/default-workflow/latest_build)

日本語辞書です

<img src="example.gif">

## Warnings
- Dictionaries can NOT be imported dynamically. They are built into the app itself. One can build the dictionary database and compile the app himself if needed.
- This app might NOT be actively developed in the future. While bug fixes will always be deployed ASAP. 

## Features
- Reasonable word ranking and search result sorting system based on robust statistic and Zipf-Mandelbrot distribution
- Automatic dealing Kanji variants according to Unihan and Japanese orthographic documents
- Incremental search with regex support
- Merging different written forms of a single word
- Fixing possible errors in dictionary data according to other dictionaries data
- Cross references by morphological analysis thanks to sudachi.rs
- Pronouncing audio via JapanesePod101 and Forvo
- Icon generated by AI using "icon of a japanese dictionary in modern art" as prompt

## [Technical Details](docs/technical-details.md)

## TODO
- sticky header
- optimize performance
  - interrupt useless query
- better history system
  - remember tile expansion status
  - refactor code
  - use sliding to switch between history pages
- optimize furigana display
- ios REGEX support
- full-width/half-width unification
- dictionary sequences and allow disable