##### George Adler
##### Last updated 2023-01-02


library(tidyverse)
library(leaflet)
library(htmlwidgets)
library(htmltools)



# The input dataset comes from the Directory of Federal Real Property (DFRP).
#   Link: https://www.tbs-sct.gc.ca/dfrp-rbif/home-accueil-eng.aspx
# Thank you to Reddit user graciejack who described the appropriate search criteria.
#   Link: https://old.reddit.com/r/CanadaPublicServants/comments/zso3hz/ottawa_offices_in_the_east_end/
# Search criteria used on the DFRP website:
#   1. Property Interest Type: Crown Owned
#   2. Property Interest Type: Lease or Licence
#   3. Property Primary Use: Office
# Then select "Export Query Results to Text File" -> "Property Records" to get the CSV file. Rename as "propertycore.csv".
# As of 2023-01-01, there are 1,839 properties in the CSV file.

property_data_path <- "data/propertycore.csv"

# Data starts on line 16 of the CSV file.
property_data <- read_csv(property_data_path, 
                          skip = 15)



# Filter the dataset to only include the properties we can map.
#   1. Remove properties with no lat/long coordinates.
#   2. Remove properties with "Protected" coordinates - these are mostly GAC properties.
#   3. Keep only properties in Canada - there is one in Singapore.
# As of 2023-01-01, there are 1,760 properties after the above filtering.
property_data_filtered <- property_data %>%
  drop_na("Latitude", "Longitude") %>%
  filter(!Latitude == "Protected") %>%
  filter(Country == "Canada")



# For mapping, we need a dataset with the lat/long coordinates and the desired popup/label text for each property.
# We also want to add GCcoworking locations as a filter option on the map.
# 1. Change lat/long column format to double, rather than the text default from import.
# 2. Convert P/Ts to their two-letter acronyms for the popup/label.
# 3. Change Latin-1 encoding to ASCII so the HTML output works properly, e.g. change the accented "e" in "Montreal" to a non-accented "e"
# 4. Add GCcoworking locations. Some of these are already listed as properties, so we will tag them accordingly.
#   Link: https://www.canada.ca/en/public-services-procurement/news/2019/06/gccoworking-new-flexible-alternative-workplaces-for-government-of-canada-employees.html
#   There are supposed to be GCcoworking locations in Vancouver and Edmonton, but their addresses appear to not be publicly available.
#     Vancouver: https://twitter.com/GccoworkingC/status/1522621444357861376 - NEED TO CHECK THIS
#   Lat/long coordinates for the manually added sites are from Google Maps.
# 5. Create the popup/label, including HTML formatting tags.
# 6. Keep only required columns for the map to shrink dataset size for performance.
property_data_for_mapping <- property_data_filtered %>%
  mutate(Latitude = as.double(Latitude), 
         Longitude = as.double(Longitude)) %>%
  mutate(province_or_territory_acronym = case_when(`Province or Territory Code (TEXT data)` == 10 ~ "NL", 
                                                   `Province or Territory Code (TEXT data)` == 11 ~ "PE", 
                                                   `Province or Territory Code (TEXT data)` == 12 ~ "NS", 
                                                   `Province or Territory Code (TEXT data)` == 13 ~ "NB", 
                                                   `Province or Territory Code (TEXT data)` == 24 ~ "QC", 
                                                   `Province or Territory Code (TEXT data)` == 35 ~ "ON", 
                                                   `Province or Territory Code (TEXT data)` == 46 ~ "MB", 
                                                   `Province or Territory Code (TEXT data)` == 47 ~ "SK", 
                                                   `Province or Territory Code (TEXT data)` == 48 ~ "AB", 
                                                   `Province or Territory Code (TEXT data)` == 59 ~ "BC", 
                                                   `Province or Territory Code (TEXT data)` == 60 ~ "YK", 
                                                   `Province or Territory Code (TEXT data)` == 61 ~ "NW", 
                                                   `Province or Territory Code (TEXT data)` == 62 ~ "NT", 
                                                   TRUE ~ "XX")) %>%
  mutate(`Property Name` = iconv(`Property Name`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(`Street Address` = iconv(`Street Address`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(Municipality = iconv(Municipality, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(gccoworking = case_when(`Property Name` %in% "L'Esplanade Laurier Site" ~ TRUE, 
                                 `Property Name` %in% "Place d'Orleans Shopping Centre Site" ~ TRUE, 
                                 `Property Name` %in% "555 Legget Drive Site" ~ TRUE, 
                                 `Property Name` %in% "480 de la Cite Boulevard Site" ~ TRUE, 
                                 `Property Name` %in% "Minto Plaza Site" ~ TRUE,    # 655 Bay Street
                                 `Property Name` %in% "3400 Jean-Beraud Avenue Site" ~ TRUE, 
                                 TRUE ~ FALSE)) %>%
  add_row(`Property Name` = "335 River Road Site", 
          `Street Address` = "335 River Road", 
          Municipality = "Ottawa", 
          province_or_territory_acronym = "ON", 
          gccoworking = TRUE, 
          Latitude = 45.31605, 
          Longitude = -75.68994) %>%
  add_row(`Property Name` = "1 Challenger Drive Site", 
          `Street Address` = "1 Challenger Drive", 
          Municipality = "Dartmouth", 
          province_or_territory_acronym = "NS", 
          gccoworking = TRUE, 
          Latitude = 44.68288, 
          Longitude = -63.61093) %>%
  mutate(popup_label = paste0("<strong>", 
                              `Property Name`, 
                              "</strong>", 
                              "<br>", 
                              `Street Address`, 
                              "<br>", 
                              Municipality, 
                              ", ", 
                              province_or_territory_acronym)) %>%
  select(popup_label, Latitude, Longitude, gccoworking)



# Mapping: first test a basic map with the properties listed and popups on click.
map_popups <- leaflet() %>%
  addTiles() %>%
  addCircles(data = property_data_for_mapping, 
             lat = ~ Latitude, 
             lng = ~ Longitude, 
             popup = ~ popup_label)

# Need to save the map output in the working directory, as there is a bug where it doesn't remove the JS dependency files if a relative path is used.
# Using unlink() is a possibility, but skipping for now to avoid potential issues in Windows.
#   https://github.com/ramnathv/htmlwidgets/issues/296
#   https://github.com/ramnathv/htmlwidgets/issues/299
#saveWidget(map_popups, file = "map_popups.html")



# Mapping: let's try it with labels (i.e. tooltips on mouse hover) rather than popups.
#   Also add groupings, for "All Offices" and "GCcoworking Locations".
# For rendering labels in HTML, we need to lapply the htmltools::HTML function on each value. This is not needed with popups.
#   https://rstudio.github.io/leaflet/showhide.html
#   https://stackoverflow.com/questions/66754341/how-to-render-html-styled-leaflet-label
map_labels <- leaflet() %>%
  addTiles() %>%
  addCircles(data = property_data_for_mapping, 
             group = "All Offices", 
             lat = ~ Latitude, 
             lng = ~ Longitude, 
             label = lapply(pull(property_data_for_mapping, popup_label), htmltools::HTML)) %>%
  addCircles(data = filter(property_data_for_mapping, gccoworking == TRUE), 
             group = "GCcoworking Locations", 
             lat = ~ Latitude, 
             lng = ~ Longitude, 
             label = lapply(pull(filter(property_data_for_mapping, gccoworking == TRUE), popup_label), htmltools::HTML)) %>%
  addLayersControl(baseGroups = c("All Offices", "GCcoworking Locations"), 
                   options = layersControlOptions(collapsed = FALSE))

saveWidget(map_labels, file = "map_labels.html")



# Mapping: now we can add a marker on mouse click, with a circle around it of radius 125 km.
# To avoid using Shiny, let's use the htmlwidgets::onRender function to add the necessary JavaScript directly.
#   https://rstudio.github.io/leaflet/morefeatures.html
#   https://stackoverflow.com/questions/32421976/update-marker-in-leaflet
#   https://stackoverflow.com/questions/39805165/delete-circle-marker-when-a-new-one-is-made
# The interactivity of the additional circle layer must be FALSE, otherwise it will cover the layer of properties and we won't see the labels on mouse hover.
#   https://stackoverflow.com/questions/66120551/leaflet-pane-style-pointerevents-none

map_goc_offices <- map_labels %>%
  onRender("
    function(el, x) {
      var myMap = this;
      var marker;
      var circle_around_marker = new L.circle({interactive: false});
      var radius = 125000;       // 125,000 m = 125 km
      
      myMap.on('click', function(e) {
        // if a marker already exists, update its position, otherwise need to create one (on the first click)
        if(marker) {
          marker.setLatLng(e.latlng);
        } else {
          marker = L.marker(e.latlng).addTo(myMap);
        }
        
        // create a circle of 125 km around the marker
        myMap.removeLayer(circle_around_marker);
        circle_around_marker = new L.circle(e.latlng, radius, {interactive: false}).addTo(myMap);
      })
    }
  ")

saveWidget(map_goc_offices, file = "map_goc_offices.html")




