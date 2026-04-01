use crate::app::App;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Style},
    symbols,
    text::{Line, Span},
    widgets::canvas::{Canvas, Line as CanvasLine, Map, MapResolution},
    widgets::{Block, Borders, Paragraph, Row, Table, Tabs, Wrap},
    Frame,
};

pub fn draw(f: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .constraints([Constraint::Length(0), Constraint::Min(0)].as_ref())
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
        0 => draw_first_tab(f, app, chunks[1]),
        1 => draw_second_tab(f, app, chunks[1]),
        2 => draw_help_tab(f, app, chunks[1]),
        _ => {}
    };
}

fn draw_first_tab(f: &mut Frame, app: &mut App, area: Rect) {
    let chunks = Layout::default()
        .constraints([Constraint::Percentage(100)].as_ref())
        .direction(Direction::Horizontal)
        .split(area);

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

            for (i, s1) in app.servers.iter().enumerate() {
                for s2 in &app.servers[i + 1..] {
                    ctx.draw(&CanvasLine {
                        x1: s1.coords.1,
                        y1: s1.coords.0,
                        y2: s2.coords.0,
                        x2: s2.coords.1,
                        color: Color::LightBlue,
                    });
                }
            }
            for server in &app.servers {
                let color = if server.status == "Up" {
                    Color::Green
                } else {
                    Color::Red
                };
                ctx.print(
                    server.coords.1,
                    server.coords.0,
                    Span::styled("X", Style::default().fg(color)),
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
    f.render_widget(map, chunks[0]);
}

fn draw_help_tab(f: &mut Frame, _app: &mut App, area: Rect) {
    let chunks = Layout::default()
        .constraints([Constraint::Percentage(100)].as_ref())
        .direction(Direction::Horizontal)
        .split(area);

    let text = vec![
        Line::from(vec![Span::styled(
            "Help: ?",
            Style::default().fg(Color::LightGreen),
        )]),
        Line::from(Span::styled(
            "Move tabs: <>",
            Style::default().fg(Color::LightGreen),
        )),
        Line::from(Span::styled(
            "Quit: q",
            Style::default().fg(Color::LightGreen),
        )),
    ];

    let p = Paragraph::new(text)
        .block(Block::default().title("Help Menu").borders(Borders::ALL))
        .style(Style::default().fg(Color::White).bg(Color::Black))
        .alignment(Alignment::Left)
        .wrap(Wrap { trim: true });

    f.render_widget(p, chunks[0]);
}

fn draw_second_tab(f: &mut Frame, app: &mut App, area: Rect) {
    let chunks = Layout::default()
        .constraints([Constraint::Percentage(100)].as_ref())
        .direction(Direction::Horizontal)
        .split(area);

    let up_style = Style::default().fg(Color::Green);

    let rows = app.servers.iter().map(|s| {
        Row::new(vec![
            String::from(&s.name),
            String::from(&s.location),
            s.status.to_string(),
            s.count.to_string(),
        ])
        .style(up_style)
    });

    let widths = [
        Constraint::Length(25),
        Constraint::Length(25),
        Constraint::Length(20),
        Constraint::Length(20),
    ];

    let table = Table::new(rows, widths)
        .header(
            Row::new(vec!["Server", "Location", "Status", "Count"])
                .style(Style::default().fg(Color::Yellow))
                .bottom_margin(1),
        )
        .block(Block::default().title("Servers").borders(Borders::ALL));

    f.render_widget(table, chunks[0]);
}
