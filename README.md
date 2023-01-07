# Mapping the locations of Government of Canada offices

The primary goal of this project is to create a simple, user-friendly map that displays the locations of all Government of Canada (GoC) offices, based on the [Directory of Federal Real Property (DFRP)](https://www.tbs-sct.gc.ca/dfrp-rbif/home-accueil-eng.aspx), and also including [GCcoworking spaces](https://www.canada.ca/en/public-services-procurement/news/2019/06/gccoworking-new-flexible-alternative-workplaces-for-government-of-canada-employees.html). 

Additionally, with the announcement of the [common hybrid work model for the Federal Public Service](https://www.canada.ca/en/government/publicservice/staffing/common-hybrid-work-model-federal-public-service.html), some public servants may be interested in examining the possibility of working from alternative workplaces within 125 km of their location, whether it be other GoC offices and/or GCcoworking locations. More information about GCcoworking is available on their [GCpedia page](https://www.gcpedia.gc.ca/wiki/GCcoworking) (only accessible from the GoC network).


## Running the code

### RStudio

If you want to run this code yourself, you can download [the repository](https://github.com/georgeadler/map-goc-offices), as well as installing [R](https://www.r-project.org/) and [RStudio](https://posit.co/products/open-source/rstudio/).

The data subfolder contains the DFRP data for GoC offices as of 2023-01-03. The R code file explains the steps needed to update the data.

### GitHub

1. Click the green `Code` button
2. Run from command line
   ``` bash
   RScript --vanilla map_goc_offices.R
   ```

This is compatible with the entire VSCode family of IDEs.

## Notes and acknowledgments

If you want to provide feedback, you can e-mail me at (my GitHub username)(at)gmail(dot)com.

While I am working as a public servant as of the time of this writing, this project was developed and released solely in my capacity as a private individual. It has no affiliation with the Government of Canada.

This project was built using R and [Leaflet](https://leafletjs.com/). The R code file includes commented links to online resources (mainly Stack Overflow) where I was able to resolve analogous issues I encountered during development. Thanks to all of those awesome people.

Thank you to Reddit user graciejack who [described the appropriate search criteria](https://old.reddit.com/r/CanadaPublicServants/comments/zso3hz/ottawa_offices_in_the_east_end/) for the DFRP.

Special thanks to Darcy Reynard for his thoughtful and valuable feedback during the development process.

