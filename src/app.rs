#[allow(dead_code)]
use rand::{
    distributions::{Distribution, Uniform},
    rngs::ThreadRng,
};
use std::{net::{IpAddr, Ipv4Addr, Ipv6Addr}, collections::HashSet, str::FromStr};
use tui::widgets::ListState;
use netstat2::*;
use sysinfo::{ProcessExt, System, SystemExt};

use maxminddb::{geoip2, Reader};

struct ProcessInfo {
    pid: u32,
    name: String,
}

struct SocketInfo {
    processes: Vec<ProcessInfo>,
    local_port: u16,
    local_addr: std::net::IpAddr,
    remote_port: Option<u16>,
    remote_addr: Option<std::net::IpAddr>,
    protocol: ProtocolFlags,
    state: Option<TcpState>,
    family: AddressFamilyFlags,
}

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

    pub fn previous(&mut self) {
        if self.index > 0 {
            self.index -= 1;
        } else {
            self.index = self.titles.len() - 1;
        }
    }
}


pub struct Server<'a> {
    pub name: &'a str,
    pub location: &'a str,
    pub coords: (f64, f64),
    pub status: &'a str,
}

pub struct App<'a> {
    pub title: &'a str,
    pub should_quit: bool,
    pub tabs: TabsState<'a>,
    pub show_chart: bool,
    pub progress: f64,
    pub reader: Reader<Vec<u8>>,
    
    
    pub servers: Vec<Server<'a>>,
    pub enhanced_graphics: bool,
}

impl<'a> App<'a> {
    pub fn new(title: &'a str, enhanced_graphics: bool) -> App<'a> {
        let reader = maxminddb::Reader::open_readfile(
            "mmdbs/GeoLite2-City.mmdb",
        ).unwrap();

        App {
            title,
            should_quit: false,
            tabs: TabsState::new(vec!["Tab0"]),
            show_chart: true,
            progress: 0.0,
            reader: reader,
            
            servers: vec![],
            enhanced_graphics,
        }
    }

    

    pub fn on_key(&mut self, c: char) {
        match c {
            'q' => {
                self.should_quit = true;
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
        let mut sockets = get_sockets(&sys, AddressFamilyFlags::IPV4);

        let mut remoteAddrs = vec![];
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
                let mut remoteAddr = s.remote_addr.clone();
                remoteAddrs.insert(count, remoteAddr);
                count = count + 1;
            }
        }        
        self.servers.clear();

        let mut count = 0;
        for x in remoteAddrs {
            
            let city: geoip2::City = match self.reader.lookup(x.unwrap()) {
                Ok(city) => {city},
                Err(_) => {
                    continue
                },
            };
            
            self.servers.insert(count, Server {
                name: "NorthAmerica-1",
                location: "New York City",
                coords: (city.location.clone().unwrap().latitude.clone().unwrap(), city.location.clone().unwrap().longitude.clone().unwrap()),
                status: "Up",
            },);

            count = count + 1;
        }
   
    }

    
}

fn get_sockets(sys: &System, addr: AddressFamilyFlags) -> Vec<SocketInfo> {
    let protos = ProtocolFlags::TCP | ProtocolFlags::UDP;
    let iterator = iterate_sockets_info(addr, protos).expect("Failed to get socket information!");

    let mut sockets: Vec<SocketInfo> = Vec::new();

    for info in iterator {
        let si = match info {
            Ok(si) => si,
            Err(_err) => {
                println!("Failed to get info for socket!");
                continue;
            }
        };

        // gather associated processes
        let process_ids = si.associated_pids;
        let mut processes: Vec<ProcessInfo> = Vec::new();
        for pid in process_ids {
            let name = match sys.get_process(pid as i32) {
                Some(pinfo) => pinfo.name(),
                None => "",
            };
            processes.push(ProcessInfo {
                pid: pid,
                name: name.to_string(),
            });
        }

        match si.protocol_socket_info {
            ProtocolSocketInfo::Tcp(tcp) => sockets.push(SocketInfo {
                processes: processes,
                local_port: tcp.local_port,
                local_addr: tcp.local_addr,
                remote_port: Some(tcp.remote_port),
                remote_addr: Some(tcp.remote_addr),
                protocol: ProtocolFlags::TCP,
                state: Some(tcp.state),
                family: addr,
            }),
            ProtocolSocketInfo::Udp(udp) => sockets.push(SocketInfo {
                processes: processes,
                local_port: udp.local_port,
                local_addr: udp.local_addr,
                remote_port: None,
                remote_addr: None,
                state: None,
                protocol: ProtocolFlags::UDP,
                family: addr,
            }),
        }
    }

    sockets
}