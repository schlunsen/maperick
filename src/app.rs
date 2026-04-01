use std::collections::{HashMap, HashSet, VecDeque};
use std::time::Instant;

use maperick::netstats::{self, get_sockets};
use netstat2::*;
use ratatui::widgets::TableState;
use sysinfo::System;

use maxminddb::{geoip2, Reader};

const SPARKLINE_WINDOW: usize = 60;

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
        self.index = self.titles.len() - 1;
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
    pub country: String,
    pub coords: (f64, f64),
    pub count: u128,
    pub ports: Vec<u16>,
    pub processes: Vec<String>,
}

/// Per-IP session history, accumulated across ticks
pub struct ServerHistory {
    pub first_seen: Instant,
    pub last_seen: Instant,
    pub times_detected: u64,
    pub total_connections: u128,
    pub all_ports: HashSet<u16>,
    pub all_processes: HashSet<String>,
    pub recent_counts: VecDeque<u64>,
    pub location: String,
    pub country: String,
}

/// Per-process aggregated view
pub struct ProcessInfo {
    pub name: String,
    pub ips: Vec<String>,
    pub total_connections: u128,
    pub ports: HashSet<u16>,
    pub coords: Vec<(f64, f64)>,
    pub locations: Vec<String>,
}

pub struct App<'a> {
    pub title: &'a str,
    pub should_quit: bool,
    pub tabs: TabsState<'a>,
    pub reader: Reader<Vec<u8>>,
    pub servers: Vec<Server>,
    pub enhanced_graphics: bool,
    pub table_state: TableState,
    pub server_history: HashMap<String, ServerHistory>,
    pub show_detail_popup: bool,
    // Processes tab
    pub process_list: Vec<ProcessInfo>,
    pub process_table_state: TableState,
}

impl<'a> App<'a> {
    pub fn new(
        title: &'a str,
        enhanced_graphics: bool,
        geodb_path: String,
    ) -> anyhow::Result<App<'a>> {
        let reader = maxminddb::Reader::open_readfile(&geodb_path).map_err(|e| {
            anyhow::anyhow!("Failed to open GeoIP database at '{}': {}", geodb_path, e)
        })?;

        let mut table_state = TableState::default();
        table_state.select(Some(0));
        let mut process_table_state = TableState::default();
        process_table_state.select(Some(0));

        Ok(App {
            title,
            should_quit: false,
            tabs: TabsState::new(vec!["Map", "Servers", "Processes", "Help"]),
            reader,
            servers: vec![],
            enhanced_graphics,
            table_state,
            server_history: HashMap::new(),
            show_detail_popup: false,
            process_list: vec![],
            process_table_state,
        })
    }

    pub fn on_right(&mut self) {
        self.tabs.next();
    }

    pub fn on_left(&mut self) {
        self.tabs.previous();
    }

    pub fn on_up(&mut self) {
        match self.tabs.index {
            1 => navigate_up(&mut self.table_state, self.servers.len()),
            2 => navigate_up(&mut self.process_table_state, self.process_list.len()),
            _ => {}
        }
    }

    pub fn on_down(&mut self) {
        match self.tabs.index {
            1 => navigate_down(&mut self.table_state, self.servers.len()),
            2 => navigate_down(&mut self.process_table_state, self.process_list.len()),
            _ => {}
        }
    }

    pub fn on_enter(&mut self) {
        if self.tabs.index == 1 && self.selected_server().is_some() {
            self.show_detail_popup = true;
        }
    }

    pub fn on_escape(&mut self) {
        if self.show_detail_popup {
            self.show_detail_popup = false;
        } else {
            self.should_quit = true;
        }
    }

    pub fn selected_server(&self) -> Option<&Server> {
        self.table_state
            .selected()
            .and_then(|i| self.servers.get(i))
    }

    #[allow(dead_code)]
    pub fn selected_server_history(&self) -> Option<&ServerHistory> {
        self.selected_server()
            .and_then(|s| self.server_history.get(&s.name))
    }

    pub fn on_key(&mut self, c: char) {
        if self.show_detail_popup {
            return; // swallow keys while popup is open
        }
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

        // Group connections by remote IP, collecting counts, ports, and process names
        let mut remote_addrs: Vec<std::net::IpAddr> = vec![];
        let mut counts: HashMap<String, u128> = HashMap::new();
        let mut ports: HashMap<String, HashSet<u16>> = HashMap::new();
        let mut procs: HashMap<String, HashSet<String>> = HashMap::new();

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
            let count = counts.entry(key.clone()).or_insert(0);
            if *count == 0 {
                remote_addrs.push(remote_addr);
            }
            *count += 1;

            if let Some(port) = s.remote_port {
                ports.entry(key.clone()).or_default().insert(port);
            }

            for p in &s.processes {
                if !p.name.is_empty() {
                    procs.entry(key.clone()).or_default().insert(p.name.clone());
                }
            }
        }

        // Remember the selected index before clearing
        let prev_selected = self.table_state.selected();
        self.servers.clear();

        // Track which IPs are active this tick (for sparkline zero-fill)
        let mut active_ips: HashSet<String> = HashSet::new();

        for addr in &remote_addrs {
            let city: geoip2::City = match self.reader.lookup(*addr) {
                Ok(city) => city,
                Err(_) => continue,
            };

            let cityname = match city.city.and_then(|c| c.names) {
                Some(names) => names.get("en").copied().unwrap_or(""),
                None => "",
            };

            let country = match city.country.and_then(|c| c.names) {
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

            let key = addr.to_string();
            let connection_count = counts.get(&key).copied().unwrap_or(1);

            let mut port_list: Vec<u16> = ports
                .get(&key)
                .map(|s| s.iter().copied().collect())
                .unwrap_or_default();
            port_list.sort();

            let mut proc_list: Vec<String> = procs
                .get(&key)
                .map(|s| s.iter().cloned().collect())
                .unwrap_or_default();
            proc_list.sort();

            // Update session history
            active_ips.insert(key.clone());
            let hist = self.server_history.entry(key).or_insert_with(|| ServerHistory {
                first_seen: Instant::now(),
                last_seen: Instant::now(),
                times_detected: 0,
                total_connections: 0,
                all_ports: HashSet::new(),
                all_processes: HashSet::new(),
                recent_counts: VecDeque::with_capacity(SPARKLINE_WINDOW),
                location: String::new(),
                country: String::new(),
            });
            hist.last_seen = Instant::now();
            hist.times_detected += 1;
            hist.total_connections += connection_count;
            hist.all_ports.extend(&port_list);
            hist.all_processes.extend(proc_list.iter().cloned());
            hist.location = String::from(cityname);
            hist.country = String::from(country);
            if hist.recent_counts.len() >= SPARKLINE_WINDOW {
                hist.recent_counts.pop_front();
            }
            hist.recent_counts.push_back(connection_count as u64);

            self.servers.push(Server {
                name: addr.to_string(),
                location: String::from(cityname),
                country: String::from(country),
                coords: location,
                count: connection_count,
                ports: port_list,
                processes: proc_list,
            });
        }

        // Zero-fill sparkline for IPs not seen this tick
        for (ip, hist) in &mut self.server_history {
            if !active_ips.contains(ip) {
                if hist.recent_counts.len() >= SPARKLINE_WINDOW {
                    hist.recent_counts.pop_front();
                }
                hist.recent_counts.push_back(0);
            }
        }

        // Restore selection, clamping to new bounds
        if !self.servers.is_empty() {
            let idx = prev_selected.unwrap_or(0).min(self.servers.len() - 1);
            self.table_state.select(Some(idx));
        }

        // Build process list
        self.rebuild_process_list();
    }

    fn rebuild_process_list(&mut self) {
        let mut proc_map: HashMap<String, ProcessInfo> = HashMap::new();

        for server in &self.servers {
            for proc_name in &server.processes {
                let entry = proc_map.entry(proc_name.clone()).or_insert_with(|| ProcessInfo {
                    name: proc_name.clone(),
                    ips: vec![],
                    total_connections: 0,
                    ports: HashSet::new(),
                    coords: vec![],
                    locations: vec![],
                });
                entry.ips.push(server.name.clone());
                entry.total_connections += server.count;
                entry.ports.extend(&server.ports);
                entry.coords.push(server.coords);
                let loc = if server.country.is_empty() {
                    server.location.clone()
                } else {
                    format!("{}, {}", server.location, server.country)
                };
                if !entry.locations.contains(&loc) {
                    entry.locations.push(loc);
                }
            }
        }

        let prev_selected = self.process_table_state.selected();
        self.process_list = proc_map.into_values().collect();
        self.process_list.sort_by(|a, b| b.total_connections.cmp(&a.total_connections));

        if !self.process_list.is_empty() {
            let idx = prev_selected.unwrap_or(0).min(self.process_list.len() - 1);
            self.process_table_state.select(Some(idx));
        }
    }
}

fn navigate_up(state: &mut TableState, len: usize) {
    let i = match state.selected() {
        Some(i) => {
            if i == 0 {
                len.saturating_sub(1)
            } else {
                i - 1
            }
        }
        None => 0,
    };
    state.select(Some(i));
}

fn navigate_down(state: &mut TableState, len: usize) {
    let i = match state.selected() {
        Some(_) if len == 0 => 0,
        Some(i) if i >= len - 1 => 0,
        Some(i) => i + 1,
        None => 0,
    };
    state.select(Some(i));
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
        assert_eq!(tabs.index, 0);
        tabs.previous();
        assert_eq!(tabs.index, 0);
    }

    #[test]
    fn test_navigate_up_wraps() {
        let mut state = TableState::default();
        state.select(Some(0));
        navigate_up(&mut state, 5);
        assert_eq!(state.selected(), Some(4));
    }

    #[test]
    fn test_navigate_down_wraps() {
        let mut state = TableState::default();
        state.select(Some(4));
        navigate_down(&mut state, 5);
        assert_eq!(state.selected(), Some(0));
    }
}
