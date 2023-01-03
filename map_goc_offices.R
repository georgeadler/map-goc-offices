##### George Adler
##### Last updated 2023-01-03



library(tidyverse)
library(leaflet)
library(htmlwidgets)
library(htmltools)



# The input datasets come from the Directory of Federal Real Property (DFRP).
#   Link: https://www.tbs-sct.gc.ca/dfrp-rbif/home-accueil-eng.aspx
# Thank you to Reddit user graciejack who described the appropriate search criteria.
#   Link: https://old.reddit.com/r/CanadaPublicServants/comments/zso3hz/ottawa_offices_in_the_east_end/
# Search criteria used on the DFRP website:
#   1. Property Interest Type: Crown Owned
#   2. Property Interest Type: Lease or Licence
#   3. Property Primary Use: Office
# Then select "Export Query Results to Text File" -> "Building Records" and "Building Tenant Records" to get the necessary CSV files.
# Rename as "structurecore.csv" and "structuretenants.csv" respectively, and place in the "data" subfolder.

structurecore_data_path <- "data/structurecore.csv"
structuretenant_data_path <- "data/structuretenant.csv"

# Data starts on line 16 of the CSV files.
structurecore_data <- read_csv(structurecore_data_path, skip = 15)
structuretenant_data <- read_csv(structuretenant_data_path, skip = 15)

# Join the building files together.
structure_joined_data <- left_join(structurecore_data, structuretenant_data, by = "Structure Number (TEXT data)")



# Filter the dataset to only include the buildings we can map.
#   1. Remove buildings with "Protected" security designation and coordinates - these are mostly GAC buildings.
#   2. Remove buildings with no lat/long coordinates.
#   3. Keep only buildings in Canada - there are a few overseas.
# As of 2023-01-03, there are 3,312 buildings after the above filtering.

structure_joined_data_filtered <- structure_joined_data %>%
  filter(`Security Designation` == "Not Protected") %>%
  drop_na("Latitude", "Longitude") %>%
  filter(Country == "Canada")



# For mapping, we need a dataset with the lat/long coordinates and the desired popup/label text for each building.
# We also want to add GCcoworking locations as a filter option on the map.
# 1. Change lat/long column format to double, rather than the text default from import.
# 2. Convert P/Ts to their two-letter acronyms for the popup/label.
# 3. Change Latin-1 encoding to ASCII so the HTML output works properly, e.g. change the accented "e" in "Montreal" to a non-accented "e".
# 4. Add GCcoworking locations. Some of these are already listed as buildings, so we will tag them accordingly.
#   https://www.canada.ca/en/public-services-procurement/news/2019/06/gccoworking-new-flexible-alternative-workplaces-for-government-of-canada-employees.html
#   There are supposed to be GCcoworking locations in Vancouver and Edmonton, but their addresses appear to not be publicly available.
#     Vancouver: https://twitter.com/GccoworkingC/status/1522621444357861376 - NEED TO CHECK THIS
#   https://msha.ke/cotravailgccoworking
#   https://www.gcpedia.gc.ca/wiki/GCcoworking [available only on the GC network]
#   https://gccollab.ca/groups/profile/2060159/engccoworkingfrcotravail-gc
#   Lat/long coordinates for the manually added sites are from Google Maps.

structure_data_cleaned <- structure_joined_data_filtered %>%
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
  mutate(`Structure Name` = iconv(`Structure Name`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(`Street Address` = iconv(`Street Address`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(Municipality = iconv(Municipality, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(gccoworking_bool = case_when(`Structure Name` %in% "L'Esplanade Laurier (commercial)" ~ TRUE, 
                                      `Structure Name` %in% "L'Esplanade Laurier - West Tower" ~ TRUE, 
                                      `Structure Name` %in% "Place d'Orleans Shopping Centre" ~ TRUE, 
                                      `Structure Name` %in% "555 Legget Drive" ~ TRUE, 
                                      `Structure Name` %in% "480 de la Cite Boulevard" ~ TRUE, 
                                      `Structure Name` %in% "Minto Plaza" ~ TRUE,    # 655 Bay Street, Toronto, ON
                                      `Structure Name` %in% "3400 Jean-Beraud Building" ~ TRUE, 
                                      TRUE ~ FALSE)) %>%
  add_row(`Structure Number (TEXT data)` = "999001",    # dummy number
          `Structure Name` = "Thornton Centre, South Wing (Building 7)", 
          `Street Address` = "335 River Road", 
          Municipality = "Ottawa", 
          province_or_territory_acronym = "ON", 
          gccoworking_bool = TRUE, 
          Latitude = 45.31606, 
          Longitude = -75.68991) %>%
  add_row(`Structure Number (TEXT data)` = "999002",    # dummy number
          `Structure Name` = "Bedford Institute of Oceanography", 
          `Street Address` = "1 Challenger Drive", 
          Municipality = "Dartmouth", 
          province_or_territory_acronym = "NS", 
          gccoworking_bool = TRUE, 
          Latitude = 44.682968, 
          Longitude = -63.610807) %>%
  add_row(`Structure Number (TEXT data)` = "999003",    # dummy number
          `Structure Name` = "800 Burrard Street, 16th Floor", 
          `Street Address` = "800 Burrard Street", 
          Municipality = "Vancouver", 
          province_or_territory_acronym = "BC", 
          gccoworking_bool = TRUE, 
          Latitude = 49.28292, 
          Longitude = -123.123055)


# 5. Create the popup/label, including HTML formatting tags.
#   The popup/label should contain information about the building's location, as well as its departmental tenant(s).
#   For each building, arrange tenants in descending order by Floor Area.
#   Example format:
#     Homer Simpson Building [this line in bold]
#     123 Fake Street
#     City, PT
#     
#     Department 1, 4,567 sq. m.
#     Department 2, 890 sq. m.
#   https://stackoverflow.com/questions/38514988/concatenate-strings-by-group-with-dplyr
# 6. Bind the two tables together. They have the same number of rows.

structure_data_labels <- structure_data_cleaned %>%
  group_by(`Structure Number (TEXT data)`) %>%
  arrange(desc(`Floor Area.y`), .by_group = TRUE) %>%
  summarise(popup_label = paste0("<strong>", 
                                 `Structure Name`, 
                                 "</strong>", 
                                 "<br>", 
                                 `Street Address`, 
                                 "<br>", 
                                 Municipality, 
                                 ", ", 
                                 province_or_territory_acronym, 
                                 "<br>", 
                                 "<br>", 
                                 paste(`Tenant Name`, paste(formatC(`Floor Area.y`, format="d", big.mark=","), "sq. m.", sep=" ", collapse=NULL), sep=", ", collapse="<br>"), 
                                 collapse = NULL)) %>%
  ungroup()

structure_data_for_mapping <- bind_cols(structure_data_cleaned, structure_data_labels)



# Mapping test: first test a basic map with the buildings listed and popups on mouse click.
test_map_popups <- leaflet() %>%
  addTiles() %>%
  addCircles(data = structure_data_for_mapping, 
             lat = ~ Latitude, 
             lng = ~ Longitude, 
             popup = ~ popup_label)

# Need to save the map output in the working directory, as there is a bug where it doesn't remove the JS dependency files if a relative path is used.
# Using unlink() is a possibility, but skipping for now to avoid potential issues in Windows.
#   https://github.com/ramnathv/htmlwidgets/issues/296
#   https://github.com/ramnathv/htmlwidgets/issues/299
#saveWidget(test_map_popups, file = "test_map_popups.html")



# For mapping, we need 3 (sets of) tables to create Leaflet layers and groups.
#   1. "All Offices": all the buildings.
#   2. "GCcoworking Locations": GCcoworking-tagged buildings only.
#   3. A set of tables, one for each tenant.
# Mapping: let's try it with labels (i.e. tooltips on mouse hover) rather than popups.
# For rendering labels in HTML, we need to lapply the htmltools::HTML function on each value. This is not needed with popups.
#   https://rstudio.github.io/leaflet/showhide.html
#   https://stackoverflow.com/questions/66754341/how-to-render-html-styled-leaflet-label

# Start with the "All Offices" and "GCcoworking Locations" layers.

table_all_offices <- structure_data_for_mapping %>%
  distinct(`Structure Number (TEXT data)...1`, .keep_all = TRUE)

table_gccoworking <- structure_data_for_mapping %>%
  filter(gccoworking_bool == TRUE) %>%
  distinct(`Structure Number (TEXT data)...1`, .keep_all = TRUE)

map_goc_offices <- leaflet() %>%
  addTiles() %>%
  addCircles(data = table_all_offices, 
             group = "All Offices", 
             lat = ~ Latitude, 
             lng = ~ Longitude, 
             label = lapply(pull(table_all_offices, popup_label), htmltools::HTML)) %>%
  addCircles(data = table_gccoworking, 
             group = "GCcoworking Locations", 
             lat = ~ Latitude, 
             lng = ~ Longitude, 
             label = lapply(pull(table_gccoworking, popup_label), htmltools::HTML))


# For the set of tenant layers, get the list of unique tenants in alphabetical order (excluding "NA").
# Then we can loop through and add a layer for each one.

list_tenant_names <- structure_data_for_mapping %>%
  distinct(`Tenant Name`) %>%
  arrange(`Tenant Name`) %>%
  drop_na()

for (i in 1:nrow(list_tenant_names)) {
  data_i <- filter(structure_data_for_mapping, `Tenant Name` == list_tenant_names$`Tenant Name`[i])
  
  map_goc_offices <- addCircles(map_goc_offices, 
                                data = data_i, 
                                group = list_tenant_names$`Tenant Name`[i], 
                                lat = ~ Latitude, 
                                lng = ~ Longitude, 
                                label = lapply(pull(data_i, popup_label), htmltools::HTML))
}


# Finally, add the selection control for the groups: users can select between "All Offices", "GCcoworking Locations", and each of the tenants individually.

map_goc_offices <- addLayersControl(map_goc_offices, 
                                    baseGroups = c("All Offices", "GCcoworking Locations", list_tenant_names$`Tenant Name`), 
                                    options = layersControlOptions(collapsed = FALSE))

saveWidget(map_goc_offices, file = "map_goc_offices.html")



# Mapping: create another version of the map, now including a marker on mouse click, with a circle around it of radius 125 km.
# To avoid using Shiny, let's use the htmlwidgets::onRender function to add the necessary JavaScript directly.
#   https://rstudio.github.io/leaflet/morefeatures.html
#   https://stackoverflow.com/questions/32421976/update-marker-in-leaflet
#   https://stackoverflow.com/questions/39805165/delete-circle-marker-when-a-new-one-is-made
# The interactivity of the additional circle layer must be FALSE, otherwise it will cover the layer of buildings and we won't see the labels on mouse hover.
#   https://stackoverflow.com/questions/66120551/leaflet-pane-style-pointerevents-none

map_goc_offices_125km <- map_goc_offices %>%
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

saveWidget(map_goc_offices_125km, file = "map_goc_offices_125km.html")



