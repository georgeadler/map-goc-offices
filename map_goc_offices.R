library(tidyverse)
library(readxl)
library(leaflet)
library(htmlwidgets)
library(htmltools)



# The input datasets come from the Directory of Federal Real Property (DFRP).
#   Link: https://www.tbs-sct.gc.ca/dfrp-rbif/home-accueil-eng.aspx
# Thank you to Reddit user graciejack who described the appropriate search criteria.
#   Link: https://old.reddit.com/r/CanadaPublicServants/comments/zso3hz/ottawa_offices_in_the_east_end/
# Search criteria used on the DFRP website:
#   1. Property Interest Type: select all checkboxes --> this will give us all the records
# Then select "Export Query Results to Text File" --> "Property Records", "Building Records", "Building Use Type Records", and "Building Tenant Records" to get the necessary CSV files.
# Rename as "propertycore.csv", "structurecore.csv", "structureuse.csv", and "structuretenant.csv" respectively, and place in the "data" subfolder.

propertycore_data_path <- "data/propertycore.csv"
structurecore_data_path <- "data/structurecore.csv"
structureuse_data_path <- "data/structureuse.csv"
structuretenant_data_path <- "data/structuretenant.csv"
offices_to_add_manually_data_path <- "data/offices_to_add_manually.xlsx"

# Data starts on line 16 of the CSV files.
propertycore_data <- read_csv(propertycore_data_path, skip = 15)
structurecore_data <- read_csv(structurecore_data_path, skip = 15)
structureuse_data <- read_csv(structureuse_data_path, skip = 15)
structuretenant_data <- read_csv(structuretenant_data_path, skip = 15)
offices_to_add_manually_data <- read_excel(offices_to_add_manually_data_path, sheet = "Offices")

# Join the building files together.
structure_joined_data <- propertycore_data %>%
  left_join(structurecore_data, by = "Property Number (TEXT data)") %>%
  left_join(structuretenant_data, by = "Structure Number (TEXT data)") %>%
  left_join(structureuse_data, by = "Structure Number (TEXT data)")



# Filter the dataset to only include the buildings we can map.
#   1. Remove buildings with "Protected" security designation and coordinates - these are mostly GAC buildings.
#   2. Remove buildings with no latitude/longitude coordinates.
#   3. Keep only buildings in Canada - there are a few overseas.
#   4. Keep only buildings with structure use type "Office" or "Law Enforcement and Corrections", or property use type "Office".
# As of 2023-01-06, there are 16,785 rows after the above filtering.
structure_joined_data_filtered <- structure_joined_data %>%
  filter(`Security Designation.y` == "Not Protected") %>%
  drop_na(`Latitude.y`, `Longitude.y`) %>%
  filter(`Country.y` == "Canada") %>%
  #filter(`Structure Use` == "Office" | `Structure Use` == "Law Enforcement and Corrections") %>%
  filter(`Structure Use` == "Office" | `Structure Use` == "Law Enforcement and Corrections" | `Primary Use Group` == "Office") %>%
  distinct(`Parcel Number (TEXT data)`, `Structure Number (TEXT data)`, `Tenant Name`, `Structure Use`, 
           .keep_all = TRUE)



# For the Correctional Service of Canada (CSC), many correctional institutions have multiple buildings which are not well-described in the structure data. So we will take their information from the property data.
# As well, all properties where CSC is the custodial organization have no (other) tenant organizations, so there is no issue with the second part (below).
structure_joined_data_filtered_csc <- structure_joined_data_filtered %>%
  filter(`Custodian Name.x` == "Correctional Service of Canada") %>%
  group_by(`Property Number (TEXT data)`) %>%
  summarise(`Property Number (TEXT data)` = first(`Property Number (TEXT data)`), 
            `Property Name` = first(`Property Name`), 
            `Structure Number (TEXT data)` = first(`Structure Number (TEXT data)`), 
            `Structure Name` = first(`Property Name`), 
            `Custodian Name.y` = first(`Custodian Name.x`), 
            `Street Address.y` = first(`Street Address.x`), 
            `Floor Area` = max(`Floor Area.x`), 
            `Municipality.y` = first(`Municipality.x`), 
            `Province or Territory Code (TEXT data).y` = first(`Province or Territory Code (TEXT data).x`), 
            `Province or Territory.y` = first(`Province or Territory.x`), 
            `Latitude.y` = first(`Latitude.x`), 
            `Longitude.y` = first(`Longitude.x`), 
            `Tenant Name` = first(`Custodian Name.x`), 
            `Floor Area` = max(`Floor Area.x`)) %>%
  ungroup() %>%
  arrange(`Structure Number (TEXT data)`)



# We need to add custodial organizations as well as tenant organizations.
# Calculate the floor area for custodial organization: (total floor area for the structure) minus (the sum of floor areas for all the tenant organizations in that structure).
# Two possibilities:
#   1. There are no tenants. In this case, make the custodial organization a tenant, with floor area equal to the total floor area for the structure.
#   2. There are tenants. In this case, add a row to make the custodial organization an additional tenant, with floor area equal to the remainder.
# Remove rows with floor area below 10 sq. m., to account for minor differences in values that sum up to the floor area, as well as generally not mapping offices that are very small.
# https://stackoverflow.com/questions/43403282/add-row-in-each-group-using-dplyr-and-add-row
structure_joined_data_filtered_allothers <- structure_joined_data_filtered %>%
  filter(`Custodian Name.x` != "Correctional Service of Canada") %>%
  group_by(`Structure Number (TEXT data)`) %>%
  mutate(sum_floor_area = case_when(is.na(`Floor Area`) ~ 0, 
                                    TRUE ~ sum(`Floor Area`))) %>%
  group_modify(~ add_row(.x, 
                         `Property Number (TEXT data)` = .x$`Property Number (TEXT data)`, 
                         `Property Name` = .x$`Property Name`, 
                         `Structure Name` = .x$`Structure Name`, 
                         `Custodian Name.y` = .x$`Custodian Name.y`, 
                         `Street Address.y` = .x$`Street Address.y`, 
                         `Floor Area.y` = .x$`Floor Area.y`, 
                         `Municipality.y` = .x$`Municipality.y`, 
                         `Province or Territory Code (TEXT data).y` = .x$`Province or Territory Code (TEXT data).y`, 
                         `Province or Territory.y` = .x$`Province or Territory.y`, 
                         `Latitude.y` = .x$`Latitude.y`, 
                         `Longitude.y` = .x$`Longitude.y`, 
                         `Tenant Name` = .x$`Custodian Name.y`, 
                         `Floor Area` = .x$`Floor Area.y` - .x$sum_floor_area)) %>%
  ungroup() %>%
  select(-sum_floor_area) %>%
  drop_na(`Tenant Name`) %>%
  filter(`Floor Area` >= 10) %>%
  select(-`Structure Use Code (TEXT data)`, -`Structure Use`) %>%
  distinct() %>%
  arrange(`Structure Number (TEXT data)`, `Floor Area`)


structure_joined_data_filtered_combined <- bind_rows(structure_joined_data_filtered_allothers, 
                                                     structure_joined_data_filtered_csc)



# For mapping, we need a dataset with the lat/long coordinates and the desired popup/label text for each building.
# We also want to add GCcoworking locations as a filter option on the map.
# 1. Change lat/long column format to double, rather than the text default from import.
# 2. Convert P/Ts to their two-letter acronyms for the popup/label.
# 3. Change Latin-1 encoding to ASCII so the HTML output works properly, e.g. change the accented "e" in "Montreal" to a non-accented "e".
# 4. Some GCcoworking locations are already listed as buildings, so we will tag them accordingly.
# 5. Add offices that must be manually added as they are not present in the DFRP data.
#     These include some GCcoworking locations, and some Canadian Grain Commission offices and service centres. See the "Notes" sheet in the Excel file for more info.

structure_data_cleaned <- structure_joined_data_filtered_combined %>%
  mutate(`Latitude.y` = as.double(`Latitude.y`), 
         `Longitude.y` = as.double(`Longitude.y`)) %>%
  mutate(province_or_territory_acronym = case_when(`Province or Territory Code (TEXT data).y` == 10 ~ "NL", 
                                                   `Province or Territory Code (TEXT data).y` == 11 ~ "PE", 
                                                   `Province or Territory Code (TEXT data).y` == 12 ~ "NS", 
                                                   `Province or Territory Code (TEXT data).y` == 13 ~ "NB", 
                                                   `Province or Territory Code (TEXT data).y` == 24 ~ "QC", 
                                                   `Province or Territory Code (TEXT data).y` == 35 ~ "ON", 
                                                   `Province or Territory Code (TEXT data).y` == 46 ~ "MB", 
                                                   `Province or Territory Code (TEXT data).y` == 47 ~ "SK", 
                                                   `Province or Territory Code (TEXT data).y` == 48 ~ "AB", 
                                                   `Province or Territory Code (TEXT data).y` == 59 ~ "BC", 
                                                   `Province or Territory Code (TEXT data).y` == 60 ~ "YT", 
                                                   `Province or Territory Code (TEXT data).y` == 61 ~ "NT", 
                                                   `Province or Territory Code (TEXT data).y` == 62 ~ "NU", 
                                                   TRUE ~ "XX")) %>%
  mutate(`Property Name` = iconv(`Property Name`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(`Structure Name` = iconv(`Structure Name`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(`Street Address.y` = iconv(`Street Address.y`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(`Municipality.y` = iconv(`Municipality.y`, from="latin1", to="ASCII//TRANSLIT")) %>%
  mutate(gccoworking_bool = case_when(`Structure Name` %in% "L'Esplanade Laurier (commercial)" ~ TRUE, 
                                      `Structure Name` %in% "L'Esplanade Laurier - West Tower" ~ TRUE, 
                                      `Structure Name` %in% "Place d'Orleans Shopping Centre" ~ TRUE, 
                                      `Structure Name` %in% "555 Legget Drive" ~ TRUE, 
                                      `Structure Name` %in% "480 de la Cite Boulevard" ~ TRUE, 
                                      `Structure Name` %in% "Minto Plaza" ~ TRUE,    # 655 Bay Street, Toronto, ON
                                      `Structure Name` %in% "3400 Jean-Beraud Building" ~ TRUE, 
                                      TRUE ~ FALSE)) %>%
  bind_rows(offices_to_add_manually_data) %>%
  arrange(`Structure Number (TEXT data)`, `Floor Area`)



# 6. Create the popup/label, including HTML formatting tags.
#   The popup/label should contain information about the building's location, as well as its organization(s).
#   For each building, arrange organizations in descending order by Floor Area.
#   Example format:
#     Homer Simpson Building [this line in bold]
#     123 Fake Street
#     City, PT
#     
#     Department 1, 4,567 sq. m.
#     Department 2, 890 sq. m.
#   https://stackoverflow.com/questions/38514988/concatenate-strings-by-group-with-dplyr
# 7. Bind the two tables together. They have the same number of rows.

# structure_data_labels <- structure_data_cleaned %>%
#   group_by(`Structure Number (TEXT data)`) %>%
#   arrange(desc(`Floor Area`), .by_group = TRUE) %>%
#   summarise(popup_label = paste0("<strong>", `Property Name`, "</strong>", "<br>", 
#                                  "<strong>", `Structure Name`, "</strong>", "<br>", 
#                                  `Street Address.y`, "<br>", 
#                                  `Municipality.y`, ", ", province_or_territory_acronym, "<br>", 
#                                  "<br>", 
#                                  paste(`Tenant Name`, paste(formatC(`Floor Area`, format="d", big.mark=","), "sq. m.", sep=" ", collapse=NULL), sep=", ", collapse="<br>"), 
#                                  collapse = NULL)) %>%
#   ungroup() %>%
#   mutate(popup_label = iconv(popup_label, from="latin1", to="ASCII//TRANSLIT"))

structure_data_labels <- structure_data_cleaned %>%
  group_by(`Structure Number (TEXT data)`) %>%
  arrange(desc(`Floor Area`), .by_group = TRUE) %>%
  summarise(popup_label = case_when(!is.na(`Property Name`) ~ paste0("<strong>", `Property Name`, "</strong>", "<br>", 
                                                                     "<strong>", `Structure Name`, "</strong>", "<br>", 
                                                                     `Street Address.y`, "<br>", 
                                                                     `Municipality.y`, ", ", province_or_territory_acronym, "<br>", 
                                                                     "<br>", 
                                                                     paste(`Tenant Name`, paste(formatC(`Floor Area`, format="d", big.mark=","), "sq. m.", sep=" ", collapse=NULL), sep=", ", collapse="<br>"), 
                                                                     collapse = NULL), 
                                    TRUE ~ paste0("<strong>", `Structure Name`, "</strong>", "<br>", 
                                                  `Street Address.y`, "<br>", 
                                                  `Municipality.y`, ", ", province_or_territory_acronym, "<br>", 
                                                  "<br>", 
                                                  paste(`Tenant Name`, paste(formatC(`Floor Area`, format="d", big.mark=","), "sq. m.", sep=" ", collapse=NULL), sep=", ", collapse="<br>"), 
                                                  collapse = NULL))) %>%
  ungroup() %>%
  mutate(popup_label = iconv(popup_label, from="latin1", to="ASCII//TRANSLIT"))

structure_data_for_mapping <- bind_cols(structure_data_cleaned, structure_data_labels)
# As of 2023-01-06, there are 5,824 rows for mapping.



# Mapping test: first test a basic map with the buildings listed and popups on mouse click.
radius_for_mapping <- 8

test_map_popups <- leaflet() %>%
  addTiles() %>%
  addCircleMarkers(data = structure_data_for_mapping, 
                   lat = ~ `Latitude.y`, 
                   lng = ~ `Longitude.y`, 
                   radius = radius_for_mapping, 
                   popup = ~ popup_label)

# Need to save the map output in the working directory, as there is a bug where it doesn't remove the JS dependency files if a relative path is used.
# Using unlink() is a possibility, but skipping for now to avoid potential issues in Windows.
#   https://github.com/ramnathv/htmlwidgets/issues/296
#   https://github.com/ramnathv/htmlwidgets/issues/299
saveWidget(test_map_popups, file = "test_map_popups.html")



# For mapping, we need 3 (sets of) tables to create Leaflet layers and groups.
#   1. "All Offices": all the buildings.
#   2. "GCcoworking Locations": GCcoworking-tagged buildings only.
#   3. A set of tables, one for each organization.
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
  addCircleMarkers(data = table_all_offices, 
                   group = "All Offices", 
                   lat = ~ `Latitude.y`, 
                   lng = ~ `Longitude.y`, 
                   radius = radius_for_mapping, 
                   label = lapply(pull(table_all_offices, popup_label), htmltools::HTML)) %>%
  addCircleMarkers(data = table_gccoworking, 
                   group = "GCcoworking Locations", 
                   lat = ~ `Latitude.y`, 
                   lng = ~ `Longitude.y`, 
                   radius = radius_for_mapping, 
                   label = lapply(pull(table_gccoworking, popup_label), htmltools::HTML))


# For the set of organization layers, get the list of unique organizations in alphabetical order (excluding "NA").
# Then we can loop through and add a layer for each one.

list_tenant_names <- structure_data_for_mapping %>%
  distinct(`Tenant Name`) %>%
  arrange(`Tenant Name`) %>%
  drop_na()

for (i in 1:nrow(list_tenant_names)) {
  data_i <- filter(structure_data_for_mapping, `Tenant Name` == list_tenant_names$`Tenant Name`[i])
  
  map_goc_offices <- addCircleMarkers(map_goc_offices, 
                                      data = data_i, 
                                      group = list_tenant_names$`Tenant Name`[i], 
                                      lat = ~ `Latitude.y`, 
                                      lng = ~ `Longitude.y`, 
                                      radius = radius_for_mapping, 
                                      label = lapply(pull(data_i, popup_label), htmltools::HTML))
}


# Finally, add the selection control for the groups: users can select between "All Offices", "GCcoworking Locations", and each of the organizations individually.
# The default selection when first loading the map should be "All Offices".

map_goc_offices <- addLayersControl(map_goc_offices, 
                                    overlayGroups = c("All Offices", "GCcoworking Locations", list_tenant_names$`Tenant Name`), 
                                    options = layersControlOptions(collapsed = FALSE)) %>%
  hideGroup(c("GCcoworking Locations", list_tenant_names$`Tenant Name`))

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




