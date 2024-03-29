# Maperick
![Workflow](https://github.com/schlunsen/maperick/actions/workflows/ci-tests.yml/badge.svg)

Show active TCP connections on a TUI world map. Still WIP, but it's gonna be good.

![](.github/screenshot.png)
![](.github/screenshot2.png)


## Setup

```
git clone git@github.com:schlunsen/maperick.git
cd maperick/

# Download mmdb city file
wget https://git.io/GeoLite2-City.mmdb

# Run maperick
cargo run -- -e -p GeoLite2-City.mmdb

# build maperick
cargo build --release

# See https://github.com/P3TERX/GeoLite.mmdb for mmdb files
./target/release/maperick -e -p GeoLite2-City.mmdb 
```

[See this repo for mmdb files](https://github.com/P3TERX/GeoLite.mmdb)
---



Dependencies
------------
* Maxmind
* rs-tui
* netstat rust



### Todo

- [x] Base setup
- [x] Replace argh with clap
- [x] Add netstat retrieval of open connections and their ip
- [x] Error handling maxdb
- [x] Add maxmind geolookup
- [x] Refactor netstats methods to module
- [x] Display connected ips in table
- [ ] Refactor on_tick code into modules
- [ ] Enable copy/paste
- [ ] Fix drawing of lines to exit from host location
- [ ] Add new tab with configuration options
- [ ] Add host public_ip as different marker on map
- [ ] Add ip's to ignore in configuration
- [ ] Add to Brew Formulae
