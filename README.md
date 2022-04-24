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
- [x] Add netstat retrieval of open connections and their ip
- [x] Error handling maxdb
- [x] Add maxmind geolookup
- [ ] Add ip's to ignore
- [ ] Replace argh with clap
- [ ] Make Geoip configurable 
- [ ] Add new tab with configuration options
- [ ] Add host public_ip as different marker on map
- [ ] Refactor alot of on_tick code into modules
- [ ] Write simple tests
- [ ] Add to Brew Formulae
- [ ] Better README
