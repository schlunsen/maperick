use crate::app::App;
use tui::{
    backend::Backend,
    layout::{Constraint, Direction, Layout, Rect, Alignment},
    style::{Color, Modifier, Style},
    symbols,
    text::{Span, Spans},
    widgets::canvas::{Canvas, Line, Map, MapResolution, },
    widgets::{
         Block, Borders,
         Row, Table, Tabs,Paragraph, Wrap
    },
    Frame,
};

pub fn draw<B: Backend>(f: &mut Frame<B>, app: &mut App) {
    let chunks = Layout::default()
        .constraints([Constraint::Length(0), Constraint::Min(0)].as_ref())
        .split(f.size());
    let titles = app
        .tabs
        .titles
        .iter()
        .map(|t| Spans::from(Span::styled(*t, Style::default().fg(Color::Green))))
        .collect();
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


fn draw_first_tab<B>(f: &mut Frame<B>, app: &mut App, area: Rect)
where
    B: Backend,
{
    let chunks = Layout::default()
        .constraints([Constraint::Percentage(100)].as_ref())
        .direction(Direction::Horizontal)
        .split(area);
    
    

    let map = Canvas::default()
        .block(Block::default().title("Connection map").borders(Borders::ALL))
        .paint(|ctx| {
            ctx.draw(&Map {
                color: Color::White,
                resolution: MapResolution::High,
            });
            ctx.layer();
            
            for (i, s1) in app.servers.iter().enumerate() {
                for s2 in &app.servers[i + 1..] {
                    ctx.draw(&Line {
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
                    Span::styled("🐴", Style::default().fg(color)),
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

fn draw_help_tab<B>(f: &mut Frame<B>, app: &mut App, area: Rect)
where
    B: Backend,
{
    let chunks = Layout::default()
    .constraints([Constraint::Percentage(100)].as_ref())
    .direction(Direction::Horizontal)
    .split(area);

    let text = vec![
    Spans::from(vec![
        Span::styled("Help: ?", Style::default().fg(Color::LightGreen))
    ]),
    Spans::from(Span::styled("Move tabs: <>", Style::default().fg(Color::LightGreen))),
    Spans::from(Span::styled("Quit: q", Style::default().fg(Color::LightGreen))),
    
];

    let p = Paragraph::new(text)
    .block(Block::default().title("Help Menu").borders(Borders::ALL))
    .style(Style::default().fg(Color::White).bg(Color::Black))
    .alignment(Alignment::Left)
    .wrap(Wrap { trim: true });
    
    f.render_widget(p, chunks[0]);
        
}


fn draw_second_tab<B>(f: &mut Frame<B>, app: &mut App, area: Rect)
where
    B: Backend,
{
    let chunks = Layout::default()
        .constraints([Constraint::Percentage(100)].as_ref())
        .direction(Direction::Horizontal)
        .split(area);
    

    let up_style = Style::default().fg(Color::Green);
    let failure_style = Style::default()
        .fg(Color::Red)
        .add_modifier(Modifier::RAPID_BLINK | Modifier::CROSSED_OUT);
    let rows = app.servers.iter().map(|s| {
        let style = if s.status == "Connected" {
            up_style
        } else {
            up_style
        };
        Row::new(vec![String::from(&s.name), String::from(&s.location), s.status.to_string(), s.count.to_string()]).style(style)
    });

    let table = Table::new(rows)
        .header(
            Row::new(vec!["Server", "Location", "Status", "Count"])
                .style(Style::default().fg(Color::Yellow))
                .bottom_margin(1),
        )
        .block(Block::default().title("Servers").borders(Borders::ALL))
        .widths(&[
            Constraint::Length(25),
            Constraint::Length(25),
            Constraint::Length(20),
            Constraint::Length(20),
        ]);

    f.render_widget(table, chunks[0]);

}


