use clap::Parser;

mod app;
#[cfg(feature = "crossterm")]
mod crossterm;
mod geodb;
#[cfg(feature = "termion")]
mod termion;
mod ui;

#[cfg(feature = "crossterm")]
use crate::crossterm::run;
#[cfg(feature = "termion")]
use crate::termion::run;
use std::time::Duration;

/// Map tcp connections on a TUI world map
#[derive(Parser, Debug)]
#[clap(name = "maperick")]
#[clap(version = "0.2")]
#[clap(about, long_about = None)]
pub struct Args {
    /// time in ms between two ticks.
    #[clap(help = "time in ms between two ticks.")]
    #[clap(short = 't', default_missing_value = "250")]
    tick_rate: Option<u64>,

    /// Path to GeoIP mmdb file. If omitted, auto-downloads to data dir.
    #[clap(short = 'p', long = "path")]
    path: Option<String>,

    /// whether unicode symbols are used to improve the overall look of the app
    #[clap(short = 'e', default_missing_value = "true")]
    enhanced_graphics: bool,

    /// Print the path where the GeoIP database is stored
    #[clap(long = "db-path", help = "Print the GeoIP database path and exit")]
    db_path: bool,
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    // --db-path: just print the location and exit
    if args.db_path {
        let path = geodb::default_db_path()?;
        println!("{}", path.display());
        return Ok(());
    }

    // Resolve the GeoIP database, downloading if needed
    let geodb_path = geodb::ensure_db(args.path.as_deref())?;
    let geodb_path_str = geodb_path.to_string_lossy().to_string();

    let tick_rate = Duration::from_millis(args.tick_rate.unwrap_or(250));

    run(tick_rate, args.enhanced_graphics, geodb_path_str)?;
    Ok(())
}
