use netstat2::*;
use sysinfo::{ProcessExt, System, SystemExt};

pub struct ProcessInfo {
    pub pid: u32,
    pub name: String,
}

pub struct SocketInfo {
    pub processes: Vec<ProcessInfo>,
    pub local_port: u16,
    pub local_addr: std::net::IpAddr,
    pub remote_port: Option<u16>,
    pub remote_addr: Option<std::net::IpAddr>,
    pub protocol: ProtocolFlags,
    pub state: Option<TcpState>,
    pub family: AddressFamilyFlags,
}

pub fn get_sockets(sys: &System, addr: AddressFamilyFlags) -> Vec<SocketInfo> {
    let protos = ProtocolFlags::TCP | ProtocolFlags::UDP;
    let iterator = match iterate_sockets_info(addr, protos) {
        Ok(iter) => iter,
        Err(e) => {
            eprintln!("Failed to get socket information: {}", e);
            return Vec::new();
        }
    };

    let mut sockets: Vec<SocketInfo> = Vec::new();

    for info in iterator {
        let si = match info {
            Ok(si) => si,
            Err(_err) => {
                eprintln!("Failed to get info for socket");
                continue;
            }
        };

        // gather associated processes
        let process_ids = si.associated_pids;
        let mut processes: Vec<ProcessInfo> = Vec::new();
        for pid in process_ids {
            let name = match sysinfo::Pid::try_from(pid as i32) {
                Ok(sysinfo_pid) => match sys.process(sysinfo_pid) {
                    Some(pinfo) => pinfo.name().to_string(),
                    None => String::new(),
                },
                Err(_) => String::new(),
            };
            processes.push(ProcessInfo { pid, name });
        }

        match si.protocol_socket_info {
            ProtocolSocketInfo::Tcp(tcp) => sockets.push(SocketInfo {
                processes,
                local_port: tcp.local_port,
                local_addr: tcp.local_addr,
                remote_port: Some(tcp.remote_port),
                remote_addr: Some(tcp.remote_addr),
                protocol: ProtocolFlags::TCP,
                state: Some(tcp.state),
                family: addr,
            }),
            ProtocolSocketInfo::Udp(udp) => sockets.push(SocketInfo {
                processes,
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
