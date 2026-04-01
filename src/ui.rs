use crate::app::App;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    symbols,
    text::{Line, Span},
    widgets::canvas::{Canvas, Map, MapResolution},
    widgets::{Block, Borders, Clear, Paragraph, Row, Sparkline, Table, Tabs, Wrap},
    Frame,
};

pub fn draw(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .constraints([Constraint::Length(3), Constraint::Min(0)].as_ref())
        .split(f.area());
    let titles = app
        .tabs
        .titles
        .iter()
        .map(|t| Line::from(Span::styled(*t, Style::default().fg(Color::Green))))
        .collect::<Vec<_>>();
    let tabs = Tabs::new(titles)
        .block(Block::default().borders(Borders::ALL).title(app.title))
        .highlight_style(Style::default().fg(Color::Yellow))
        .select(app.tabs.index);
    f.render_widget(tabs, chunks[0]);
    match app.tabs.index {
        0 => draw_map_tab(f, app, chunks[1]),
        1 => draw_servers_tab(f, app, chunks[1]),
        2 => draw_processes_tab(f, app, chunks[1]),
        3 => draw_help_tab(f, app, chunks[1]),
        _ => {}
    };

    // Render popup overlay on top of everything
    if app.show_detail_popup {
        draw_detail_popup(f, app);
    }
}

fn draw_map_tab(f: &mut Frame, app: &mut App, area: Rect) {
    let map = Canvas::default()
        .block(
            Block::default()
                .title("Connection map")
                .borders(Borders::ALL),
        )
        .paint(|ctx| {
            ctx.draw(&Map {
                color: Color::White,
                resolution: MapResolution::High,
            });
            ctx.layer();

            for server in &app.servers {
                let color = match server.count {
                    1 => Color::Green,
                    2..=5 => Color::Yellow,
                    _ => Color::Red,
                };
                ctx.print(
                    server.coords.1,
                    server.coords.0,
                    Span::styled("●", Style::default().fg(color)),
                );
            }
        })
        .marker(if app.enhanced_graphics {
            symbols::Marker::Braille
        } else {
            symbols::Marker::Block
        })
        .x_bounds([-180.0, 180.0])
        .y_bounds([-90.0, 90.0]);
    f.render_widget(map, area);
}

fn draw_servers_tab(f: &mut Frame, app: &mut App, area: Rect) {
    let chunks = Layout::default()
        .constraints([Constraint::Min(10), Constraint::Length(10)].as_ref())
        .direction(Direction::Vertical)
        .split(area);

    let normal_style = Style::default().fg(Color::Green);
    let selected_style = Style::default()
        .fg(Color::Black)
        .bg(Color::LightGreen)
        .add_modifier(Modifier::BOLD);

    let rows = app.servers.iter().map(|s| {
        let proc_str = if s.processes.is_empty() {
            String::from("-")
        } else {
            s.processes.join(", ")
        };
        Row::new(vec![
            String::from(&s.name),
            String::from(&s.location),
            proc_str,
            s.count.to_string(),
        ])
        .style(normal_style)
    });

    let widths = [
        Constraint::Length(20),
        Constraint::Length(28),
        Constraint::Length(20),
        Constraint::Length(8),
    ];

    let table = Table::new(rows, widths)
        .header(
            Row::new(vec!["Server", "Location", "Process", "Count"])
                .style(
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                )
                .bottom_margin(1),
        )
        .block(
            Block::default()
                .title("Servers (↑↓ select, Enter details)")
                .borders(Borders::ALL),
        )
        .row_highlight_style(selected_style)
        .highlight_symbol("► ");

    f.render_stateful_widget(table, chunks[0], &mut app.table_state);

    // Detail pane
    let detail_text = if let Some(server) = app.selected_server() {
        let ports_str = if server.ports.is_empty() {
            String::from("-")
        } else {
            server
                .ports
                .iter()
                .map(|p| format_port(*p))
                .collect::<Vec<_>>()
                .join(", ")
        };
        let procs_str = if server.processes.is_empty() {
            String::from("-")
        } else {
            server.processes.join(", ")
        };

        vec![
            Line::from(vec![
                Span::styled("  IP: ", Style::default().fg(Color::DarkGray)),
                Span::styled(
                    &server.name,
                    Style::default()
                        .fg(Color::White)
                        .add_modifier(Modifier::BOLD),
                ),
            ]),
            Line::from(vec![
                Span::styled("  Location: ", Style::default().fg(Color::DarkGray)),
                Span::styled(
                    format!("{}, {}", server.location, server.country),
                    Style::default().fg(Color::White),
                ),
            ]),
            Line::from(vec![
                Span::styled("  Connections: ", Style::default().fg(Color::DarkGray)),
                Span::styled(
                    server.count.to_string(),
                    Style::default().fg(Color::LightGreen),
                ),
            ]),
            Line::from(vec![
                Span::styled("  Ports: ", Style::default().fg(Color::DarkGray)),
                Span::styled(ports_str, Style::default().fg(Color::LightCyan)),
            ]),
            Line::from(vec![
                Span::styled("  Processes: ", Style::default().fg(Color::DarkGray)),
                Span::styled(procs_str, Style::default().fg(Color::LightMagenta)),
            ]),
        ]
    } else {
        vec![Line::from(Span::styled(
            "  No server selected",
            Style::default().fg(Color::DarkGray),
        ))]
    };

    let detail = Paragraph::new(detail_text)
        .block(Block::default().title("Details").borders(Borders::ALL))
        .style(Style::default().fg(Color::White));

    f.render_widget(detail, chunks[1]);
}

fn draw_processes_tab(f: &mut Frame, app: &mut App, area: Rect) {
    // Split: left side (table + detail), right side (map)
    let h_chunks = Layout::default()
        .constraints([Constraint::Percentage(45), Constraint::Percentage(55)].as_ref())
        .direction(Direction::Horizontal)
        .split(area);

    // Left side: table on top, detail below
    let left_chunks = Layout::default()
        .constraints([Constraint::Min(8), Constraint::Length(8)].as_ref())
        .direction(Direction::Vertical)
        .split(h_chunks[0]);

    let normal_style = Style::default().fg(Color::Green);
    let selected_style = Style::default()
        .fg(Color::Black)
        .bg(Color::LightMagenta)
        .add_modifier(Modifier::BOLD);

    let rows = app.process_list.iter().map(|p| {
        Row::new(vec![
            p.name.clone(),
            p.ips.len().to_string(),
            p.total_connections.to_string(),
        ])
        .style(normal_style)
    });

    let widths = [
        Constraint::Length(22),
        Constraint::Length(6),
        Constraint::Length(8),
    ];

    let table = Table::new(rows, widths)
        .header(
            Row::new(vec!["Process", "IPs", "Conns"])
                .style(
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                )
                .bottom_margin(1),
        )
        .block(
            Block::default()
                .title("Processes (↑↓)")
                .borders(Borders::ALL),
        )
        .row_highlight_style(selected_style)
        .highlight_symbol("► ");

    f.render_stateful_widget(table, left_chunks[0], &mut app.process_table_state);

    // Detail pane (bottom-left)
    let selected_proc = app
        .process_table_state
        .selected()
        .and_then(|i| app.process_list.get(i));

    let detail_text = if let Some(proc) = selected_proc {
        let ports_str: String = {
            let mut sorted: Vec<u16> = proc.ports.iter().copied().collect();
            sorted.sort();
            sorted
                .iter()
                .take(6)
                .map(|port| format_port(*port))
                .collect::<Vec<_>>()
                .join(", ")
        };
        let locations_str = proc.locations.join(", ");
        vec![
            Line::from(vec![
                Span::styled(" ", Style::default()),
                Span::styled(
                    &proc.name,
                    Style::default()
                        .fg(Color::LightMagenta)
                        .add_modifier(Modifier::BOLD),
                ),
                Span::styled(
                    format!("  {} IPs, {} conns", proc.ips.len(), proc.total_connections),
                    Style::default().fg(Color::DarkGray),
                ),
            ]),
            Line::from(vec![
                Span::styled(" Ports: ", Style::default().fg(Color::DarkGray)),
                Span::styled(ports_str, Style::default().fg(Color::LightCyan)),
            ]),
            Line::from(vec![
                Span::styled(" Locations: ", Style::default().fg(Color::DarkGray)),
                Span::styled(locations_str, Style::default().fg(Color::White)),
            ]),
        ]
    } else {
        vec![Line::from(Span::styled(
            "  No process selected",
            Style::default().fg(Color::DarkGray),
        ))]
    };

    let detail = Paragraph::new(detail_text)
        .block(Block::default().title("Details").borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .wrap(Wrap { trim: true });

    f.render_widget(detail, left_chunks[1]);

    // Right side: mini map filtered to selected process's connections
    let proc_coords: Vec<(f64, f64)> = selected_proc.map(|p| p.coords.clone()).unwrap_or_default();

    let proc_name_title = selected_proc
        .map(|p| format!("Map: {}", p.name))
        .unwrap_or_else(|| "Map".to_string());

    let map = Canvas::default()
        .block(
            Block::default()
                .title(proc_name_title)
                .borders(Borders::ALL),
        )
        .paint(move |ctx| {
            ctx.draw(&Map {
                color: Color::DarkGray,
                resolution: MapResolution::High,
            });
            ctx.layer();

            for &(lat, lon) in &proc_coords {
                ctx.print(
                    lon,
                    lat,
                    Span::styled(
                        "●",
                        Style::default()
                            .fg(Color::LightMagenta)
                            .add_modifier(Modifier::BOLD),
                    ),
                );
            }
        })
        .marker(if app.enhanced_graphics {
            symbols::Marker::Braille
        } else {
            symbols::Marker::Block
        })
        .x_bounds([-180.0, 180.0])
        .y_bounds([-90.0, 90.0]);

    f.render_widget(map, h_chunks[1]);
}

fn draw_help_tab(f: &mut Frame, _app: &mut App, area: Rect) {
    let text = vec![
        Line::from(""),
        Line::from(vec![
            Span::styled(
                "  ← → ",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled("Switch tabs", Style::default().fg(Color::White)),
        ]),
        Line::from(vec![
            Span::styled(
                "  ↑ ↓ ",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                "Navigate server/process list",
                Style::default().fg(Color::White),
            ),
        ]),
        Line::from(vec![
            Span::styled(
                "  Enter ",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                "Open detailed stats for selected server",
                Style::default().fg(Color::White),
            ),
        ]),
        Line::from(vec![
            Span::styled(
                "  Esc ",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled("Close popup / Quit", Style::default().fg(Color::White)),
        ]),
        Line::from(vec![
            Span::styled(
                "  q ",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled("Quit", Style::default().fg(Color::White)),
        ]),
        Line::from(vec![
            Span::styled(
                "  h ",
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled("Show this help", Style::default().fg(Color::White)),
        ]),
    ];

    let p = Paragraph::new(text)
        .block(Block::default().title("Help").borders(Borders::ALL))
        .style(Style::default().fg(Color::White))
        .alignment(Alignment::Left)
        .wrap(Wrap { trim: true });

    f.render_widget(p, area);
}

fn draw_detail_popup(f: &mut Frame, app: &mut App) {
    let area = centered_rect(65, 75, f.area());

    // Clear background
    f.render_widget(Clear, area);

    // Get server and history data
    let server = match app.selected_server() {
        Some(s) => s,
        None => {
            app.show_detail_popup = false;
            return;
        }
    };
    let ip = server.name.clone();
    let location = format!("{}, {}", server.location, server.country);
    let current_count = server.count;
    let current_ports = server
        .ports
        .iter()
        .map(|p| format_port(*p))
        .collect::<Vec<_>>()
        .join(", ");
    let current_procs = server.processes.join(", ");

    let history = app.server_history.get(&ip);

    // Build text content
    let mut lines = vec![
        Line::from(""),
        Line::from(vec![
            Span::styled("  IP: ", Style::default().fg(Color::DarkGray)),
            Span::styled(
                &ip,
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD),
            ),
        ]),
        Line::from(vec![
            Span::styled("  Location: ", Style::default().fg(Color::DarkGray)),
            Span::styled(&location, Style::default().fg(Color::White)),
        ]),
        Line::from(vec![
            Span::styled(
                "  Current connections: ",
                Style::default().fg(Color::DarkGray),
            ),
            Span::styled(
                current_count.to_string(),
                Style::default().fg(Color::LightGreen),
            ),
        ]),
        Line::from(""),
    ];

    if let Some(hist) = history {
        let duration = hist.last_seen.duration_since(hist.first_seen);
        let duration_str = format_duration(duration);
        let avg = if hist.times_detected > 0 {
            hist.total_connections as f64 / hist.times_detected as f64
        } else {
            0.0
        };

        // Frequency bar
        let recent: Vec<u64> = hist.recent_counts.iter().copied().collect();
        let active_ticks = recent.iter().filter(|&&c| c > 0).count();
        let freq_pct = if !recent.is_empty() {
            (active_ticks as f64 / recent.len() as f64 * 100.0) as u32
        } else {
            0
        };
        let filled = (freq_pct as usize) / 5;
        let empty = 20 - filled.min(20);
        let freq_bar = format!(
            "{}{} {}%",
            "█".repeat(filled.min(20)),
            "░".repeat(empty),
            freq_pct
        );

        lines.extend(vec![
            Line::from(Span::styled(
                "  ── Session Stats ──────────────────────────",
                Style::default().fg(Color::DarkGray),
            )),
            Line::from(vec![
                Span::styled("  Tracking for: ", Style::default().fg(Color::DarkGray)),
                Span::styled(duration_str, Style::default().fg(Color::White)),
            ]),
            Line::from(vec![
                Span::styled("  Times detected: ", Style::default().fg(Color::DarkGray)),
                Span::styled(
                    format!("{} polling cycles", hist.times_detected),
                    Style::default().fg(Color::LightGreen),
                ),
            ]),
            Line::from(vec![
                Span::styled(
                    "  Total connections: ",
                    Style::default().fg(Color::DarkGray),
                ),
                Span::styled(
                    hist.total_connections.to_string(),
                    Style::default().fg(Color::LightGreen),
                ),
            ]),
            Line::from(vec![
                Span::styled(
                    "  Avg per detection: ",
                    Style::default().fg(Color::DarkGray),
                ),
                Span::styled(format!("{:.1}", avg), Style::default().fg(Color::White)),
            ]),
            Line::from(vec![
                Span::styled("  Frequency: ", Style::default().fg(Color::DarkGray)),
                Span::styled(freq_bar, Style::default().fg(Color::LightCyan)),
            ]),
            Line::from(""),
        ]);

        // All-time ports
        let mut all_ports: Vec<u16> = hist.all_ports.iter().copied().collect();
        all_ports.sort();
        let all_ports_str = all_ports
            .iter()
            .map(|p| format_port(*p))
            .collect::<Vec<_>>()
            .join(", ");

        let mut all_procs: Vec<&String> = hist.all_processes.iter().collect();
        all_procs.sort();
        let all_procs_str = all_procs
            .iter()
            .map(|s| s.as_str())
            .collect::<Vec<_>>()
            .join(", ");

        lines.extend(vec![
            Line::from(Span::styled(
                "  ── All-Time (this session) ────────────────",
                Style::default().fg(Color::DarkGray),
            )),
            Line::from(vec![
                Span::styled("  Ports seen: ", Style::default().fg(Color::DarkGray)),
                Span::styled(all_ports_str, Style::default().fg(Color::LightCyan)),
            ]),
            Line::from(vec![
                Span::styled("  Processes: ", Style::default().fg(Color::DarkGray)),
                Span::styled(all_procs_str, Style::default().fg(Color::LightMagenta)),
            ]),
        ]);
    }

    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("  Current ports: ", Style::default().fg(Color::DarkGray)),
        Span::styled(&current_ports, Style::default().fg(Color::LightCyan)),
    ]));
    lines.push(Line::from(vec![
        Span::styled(
            "  Current processes: ",
            Style::default().fg(Color::DarkGray),
        ),
        Span::styled(&current_procs, Style::default().fg(Color::LightMagenta)),
    ]));

    // Split popup area: text + sparkline
    let popup_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(0), Constraint::Length(5)])
        .split(area);

    let popup = Paragraph::new(lines)
        .block(
            Block::default()
                .title(" Server Detail ── Esc to close ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::LightCyan)),
        )
        .style(Style::default().fg(Color::White))
        .wrap(Wrap { trim: true });

    f.render_widget(popup, popup_chunks[0]);

    // Sparkline showing recent connection counts
    if let Some(hist) = app.server_history.get(&ip) {
        let data: Vec<u64> = hist.recent_counts.iter().copied().collect();
        let sparkline = Sparkline::default()
            .block(
                Block::default()
                    .title(" Connections (last 60 ticks) ")
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::LightCyan)),
            )
            .data(&data)
            .style(Style::default().fg(Color::LightGreen));

        f.render_widget(sparkline, popup_chunks[1]);
    }
}

/// Helper to create a centered rect
fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);
    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}

/// Format a duration into a human-readable string
fn format_duration(d: std::time::Duration) -> String {
    let secs = d.as_secs();
    if secs < 60 {
        format!("{}s", secs)
    } else if secs < 3600 {
        format!("{}m {}s", secs / 60, secs % 60)
    } else {
        format!("{}h {}m", secs / 3600, (secs % 3600) / 60)
    }
}

/// Map well-known ports to service names
fn format_port(port: u16) -> String {
    let service = match port {
        22 => "SSH",
        53 => "DNS",
        80 => "HTTP",
        443 => "HTTPS",
        993 => "IMAPS",
        995 => "POP3S",
        3306 => "MySQL",
        5432 => "PostgreSQL",
        6379 => "Redis",
        8080 => "HTTP-Alt",
        8443 => "HTTPS-Alt",
        _ => "",
    };
    if service.is_empty() {
        format!("{}", port)
    } else {
        format!("{} ({})", port, service)
    }
}
