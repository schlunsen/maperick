use clap::Parser;

mod app;
#[cfg(feature = "crossterm")]
mod crossterm;
#[cfg(feature = "termion")]
mod termion;
mod ui;

#[cfg(feature = "crossterm")]
use crate::crossterm::run;
#[cfg(feature = "termion")]
use crate::termion::run;
use std::{error::Error, time::Duration};



/// Map tcp connections on a TUI world map
#[derive(Parser, Debug)]
#[clap(name = "maperick")]
#[clap(version = "0.1")]
#[clap(about, long_about = None)]
pub struct Args {
    /// time in ms between two ticks.
    #[clap(takes_value = false)]
    #[clap(help = "time in ms between two ticks.")]
    #[clap(short = 't', default_missing_value = "250")]
    tick_rate: Option<u64>,

    #[clap(takes_value = false)]
    #[clap(help = "Path to geolite2 db")]
    #[clap(short = 'p', default_missing_value = "mmdbs/GeoLite2-City.mmdb")]
    path: Option<String>,

    /// whether unicode symbols are used to improve the overall look of the app
    #[clap(short = 'e', default_missing_value = "true",)]
    enhanced_graphics: bool,
}



fn main() -> Result<(), Box<dyn Error>> {

    let args =  Args::parse();

    let tick_rate = if args.tick_rate.unwrap_or(0) > 0 { Duration::from_millis(args.tick_rate.expect("")) } else { Duration::from_millis(250) };
    
    let geodb_path =  match args.path {
        Some(p) => { p },
        None => { String::from("mmdbs/GeoLite2-City.mmdb") },
     };
    
    run(tick_rate, args.enhanced_graphics, geodb_path)?;
    Ok(())
}
