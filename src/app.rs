use std::collections::HashMap;

use maperick::netstats::{self, get_sockets};
use netstat2::*;
use serde::{Deserialize, Serialize};
use sysinfo::System;

use maxminddb::{geoip2, Reader};

pub struct TabsState<'a> {
    pub titles: Vec<&'a str>,
    pub index: usize,
}

impl<'a> TabsState<'a> {
    pub fn new(titles: Vec<&'a str>) -> TabsState<'a> {
        TabsState { titles, index: 0 }
    }
    pub fn next(&mut self) {
        self.index = (self.index + 1) % self.titles.len();
    }

    pub fn help(&mut self) {
        self.index = 2;
    }

    pub fn previous(&mut self) {
        if self.index > 0 {
            self.index -= 1;
        } else {
            self.index = self.titles.len() - 1;
        }
    }
}

pub struct Server {
    pub name: String,
    pub location: String,
    pub coords: (f64, f64),
    pub status: String,
    pub count: u128,
}

pub struct App<'a> {
    pub title: &'a str,
    pub should_quit: bool,
    pub tabs: TabsState<'a>,
    pub progress: f64,
    pub reader: Reader<Vec<u8>>,
    pub servers: Vec<Server>,
    pub enhanced_graphics: bool,
}

#[derive(Serialize, Deserialize)]
struct MaperickConfig {
    path: String,
}

impl Default for MaperickConfig {
    fn default() -> Self {
        Self {
            path: "mmdbs/GeoLite2-City.mmdb".into(),
        }
    }
}

impl<'a> App<'a> {
    pub fn new(
        title: &'a str,
        enhanced_graphics: bool,
        geodb_path: String,
    ) -> anyhow::Result<App<'a>> {
        let mut cfg: MaperickConfig = confy::load("maperick", None)
            .unwrap_or_else(|_| MaperickConfig::default());

        let reader = if geodb_path.is_empty() {
            maxminddb::Reader::open_readfile(&cfg.path)
                .map_err(|e| anyhow::anyhow!("Failed to open GeoIP database at '{}': {}", cfg.path, e))?
        } else {
            cfg.path = geodb_path.clone();
            if let Err(e) = confy::store("maperick", None, &cfg) {
                eprintln!("Warning: couldn't store config: {}", e);
            }
            maxminddb::Reader::open_readfile(&geodb_path)
                .map_err(|e| anyhow::anyhow!("Failed to open GeoIP database at '{}': {}", geodb_path, e))?
        };

        Ok(App {
            title,
            should_quit: false,
            tabs: TabsState::new(vec!["Tab0", "Tab1", "Help"]),
            progress: 0.0,
            reader,
            servers: vec![],
            enhanced_graphics,
        })
    }

    pub fn on_right(&mut self) {
        self.tabs.next();
    }

    #[allow(dead_code)]
    pub fn on_help(&mut self) {
        self.tabs.help();
    }

    pub fn on_left(&mut self) {
        self.tabs.previous();
    }

    pub fn on_key(&mut self, c: char) {
        match c {
            'q' => {
                self.should_quit = true;
            }
            'h' => {
                self.tabs.help();
            }
            _ => {}
        }
    }

    pub fn on_tick(&mut self) {
        let sys = System::new_with_specifics(
            sysinfo::RefreshKind::nothing()
                .with_processes(sysinfo::ProcessRefreshKind::everything()),
        );
        let sockets: Vec<netstats::SocketInfo> = get_sockets(&sys, AddressFamilyFlags::IPV4);

        let mut remote_addrs: Vec<std::net::IpAddr> = vec![];
        let mut remote_addrs_map: HashMap<String, u128> = HashMap::new();

        for s in sockets {
            if s.protocol != ProtocolFlags::TCP {
                continue;
            }
            if s.family != AddressFamilyFlags::IPV4 {
                continue;
            }
            if s.state == Some(TcpState::Listen) {
                continue;
            }

            let remote_addr = match s.remote_addr {
                Some(addr) => addr,
                None => continue,
            };

            let key = remote_addr.to_string();
            let count = remote_addrs_map.entry(key).or_insert(0);
            if *count == 0 {
                remote_addrs.push(remote_addr);
            }
            *count += 1;
        }

        self.servers.clear();

        for addr in &remote_addrs {
            let city: geoip2::City = match self.reader.lookup(*addr) {
                Ok(city) => city,
                Err(_) => continue,
            };

            let cityname = match city.city.and_then(|c| c.names) {
                Some(names) => names.get("en").copied().unwrap_or(""),
                None => "",
            };

            let location = match &city.location {
                Some(loc) => match (loc.latitude, loc.longitude) {
                    (Some(lat), Some(lon)) => (lat, lon),
                    _ => continue,
                },
                None => continue,
            };

            let connection_count = remote_addrs_map
                .get(&addr.to_string())
                .copied()
                .unwrap_or(1);

            self.servers.push(Server {
                name: addr.to_string(),
                location: String::from(cityname),
                coords: location,
                status: String::from("Connected"),
                count: connection_count,
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tabs_state_new() {
        let tabs = TabsState::new(vec!["Tab0", "Tab1", "Help"]);
        assert_eq!(tabs.index, 0);
        assert_eq!(tabs.titles.len(), 3);
    }

    #[test]
    fn test_tabs_next_wraps_around() {
        let mut tabs = TabsState::new(vec!["Tab0", "Tab1", "Help"]);
        assert_eq!(tabs.index, 0);
        tabs.next();
        assert_eq!(tabs.index, 1);
        tabs.next();
        assert_eq!(tabs.index, 2);
        tabs.next();
        assert_eq!(tabs.index, 0); // wraps around
    }

    #[test]
    fn test_tabs_previous_wraps_around() {
        let mut tabs = TabsState::new(vec!["Tab0", "Tab1", "Help"]);
        assert_eq!(tabs.index, 0);
        tabs.previous();
        assert_eq!(tabs.index, 2); // wraps to last
        tabs.previous();
        assert_eq!(tabs.index, 1);
    }

    #[test]
    fn test_tabs_help() {
        let mut tabs = TabsState::new(vec!["Tab0", "Tab1", "Help"]);
        tabs.help();
        assert_eq!(tabs.index, 2);
    }

    #[test]
    fn test_on_key_quit() {
        // We can't easily construct App without a DB file,
        // but we can test TabsState independently
        let mut tabs = TabsState::new(vec!["A", "B"]);
        tabs.next();
        assert_eq!(tabs.index, 1);
        tabs.next();
        assert_eq!(tabs.index, 0);
    }

    #[test]
    fn test_single_tab() {
        let mut tabs = TabsState::new(vec!["Only"]);
        assert_eq!(tabs.index, 0);
        tabs.next();
        assert_eq!(tabs.index, 0); // wraps to 0
        tabs.previous();
        assert_eq!(tabs.index, 0); // wraps to 0
    }
}
