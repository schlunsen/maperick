# Maperick
![Workflow](https://github.com/schlunsen/maperick/actions/workflows/ci-tests.yml/badge.svg)

Show connected ip addresses to your terminal on a TUI world map! 

![](screenshot.png)



## Setup

```
# Run maperick
cargo run 

# build maperick
cargo build --release
```


Dependencies
------------
* Maxmind
* rs-tui
* netstat rust



### Todo

- [x] Base setup
- [ ] Add ip's to ignore
- [ ] Replace argh with clap
- [ ] Add netstat retrieval of open connections and their ip
- [ ] Add maxmind geolookup
- [ ] Better README
- [x] Error handling maxdb
- [ ] Write simple tests
