use rand::{
    distributions::{Distribution, Uniform},
    rngs::ThreadRng,
};
use tui::widgets::ListState;


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
    
    
    pub servers: Vec<Server<'a>>,
    pub enhanced_graphics: bool,
}

impl<'a> App<'a> {
    pub fn new(title: &'a str, enhanced_graphics: bool) -> App<'a> {
        

        App {
            title,
            should_quit: false,
            tabs: TabsState::new(vec!["Tab0"]),
            show_chart: true,
            progress: 0.0,
            
            servers: vec![
                // Server {
                //     name: "NorthAmerica-1",
                //     location: "New York City",
                //     coords: (41.3828939, 2.1774322),
                //     status: "Up",
                // },
                // Server {
                //     name: "Europe-1",
                //     location: "Paris",
                //     coords: (48.85, 2.35),
                //     status: "Failure",
                // },
                // Server {
                //     name: "SouthAmerica-1",
                //     location: "São Paulo",
                //     coords: (-23.54, -46.62),
                //     status: "Up",
                // },
                // Server {
                //     name: "Asia-1",
                //     location: "Singapore",
                //     coords: (1.35, 103.86),
                //     status: "Up",
                // },
            ],
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


        self.servers.insert(self.servers.len(), Server {
            name: "NorthAmerica-1",
            location: "New York City",
            coords: (41.3828939+self.progress, 2.1774322),
            status: "Up",
        },);
        
    }
}
