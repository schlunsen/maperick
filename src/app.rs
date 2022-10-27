use std::collections::HashMap;

use maperick::netstats::{self, get_sockets};
use netstat2::*;
use serde::{Deserialize, Serialize};
use sysinfo::{System, SystemExt};
extern crate confy;

use maxminddb::{geoip2, Reader};

pub struct TabsState<'a> {
    pub titles: Vec<&'a str>,
    pub index: usize,
}

impl<'a> TabsState<'a> {
    pub fn new(titles: Vec<&'a str>) -> TabsState {
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
    pub show_chart: bool,
    pub progress: f64,
    pub reader: Reader<Vec<u8>>,

    pub servers: Vec<Server>,
    pub enhanced_graphics: bool,
}

#[derive(Serialize, Deserialize)]
struct MaperickConfig {
    path: String,
}
/// `MaperickConfig` implements `Default`
impl ::std::default::Default for MaperickConfig {
    fn default() -> Self {
        Self {
            path: "mmdbs/GeoLite2-City.mmdb".into(),
        }
    }
}

impl<'a> App<'a> {
    pub fn new(title: &'a str, enhanced_graphics: bool, geodb_path: String) -> App<'a> {
        let mut cfg: MaperickConfig = confy::load("maperick", None).unwrap();

        let reader = match geodb_path.len() {
            0 => maxminddb::Reader::open_readfile(cfg.path).unwrap(),
            _ => {
                cfg.path = geodb_path.clone();
                // Store path for later use, if not path not provided as argument.
                confy::store("maperick", None, cfg).expect("Couldn't store config");

                maxminddb::Reader::open_readfile(geodb_path).unwrap()
            }
        };

        App {
            title,
            should_quit: false,
            tabs: TabsState::new(vec!["Tab0", "Tab1", "Help"]),
            show_chart: true,
            progress: 0.0,
            reader: reader,
            servers: vec![],
            enhanced_graphics,
        }
    }

    pub fn on_right(&mut self) {
        self.tabs.next();
    }
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
        // Update progress
        self.progress += 1.111;
        if self.progress > 1.0 {
            //self.progress = 0.0;
        }

        let sys = System::new_all();
        let sockets: Vec<netstats::SocketInfo> = get_sockets(&sys, AddressFamilyFlags::IPV4);

        let mut remote_addrs = vec![];
        let mut remote_addrs_map: HashMap<String, u128> = HashMap::new();
        let mut count = 0;
        for s in sockets {
            if s.protocol != ProtocolFlags::TCP {
                continue;
            }

            let ip_ver = if s.family == AddressFamilyFlags::IPV4 {
                "4"
            } else {
                "6"
            };

            if ip_ver == "6" {
                continue;
            }

            if s.state == Some(TcpState::Listen) {
            } else {
                let remote_addr = s.remote_addr.clone();
                let entry = remote_addrs_map.get(&remote_addr.unwrap().to_string());

                if entry.is_some() {
                    remote_addrs_map.insert(remote_addr.unwrap().to_string(), entry.unwrap() + 1);
                } else {
                    remote_addrs_map.insert(remote_addr.unwrap().to_string(), 1);
                    remote_addrs.insert(count, remote_addr);
                    count = count + 1;
                }
            }
        }
        self.servers.clear();

        let mut count = 0;
        for x in remote_addrs {
            let city: geoip2::City = match self.reader.lookup(x.unwrap()) {
                Ok(city) => city,
                Err(_) => continue,
            };
            let cityname = match city.city.and_then(|c| c.names) {
                Some(names) => names.get("en").unwrap_or(&""),
                None => "",
            };

            let connection_count = remote_addrs_map.get(&x.unwrap().to_string()).unwrap();

            self.servers.insert(
                count,
                Server {
                    name: x.unwrap().to_string(),
                    location: String::from(cityname),
                    coords: (
                        city.location.clone().unwrap().latitude.clone().unwrap(),
                        city.location.clone().unwrap().longitude.clone().unwrap(),
                    ),
                    status: String::from("Connected"),
                    count: *connection_count,
                },
            );

            count = count + 1;
        }
    }
}
