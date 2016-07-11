library(readr)
library(dplyr)
library(lubridate)
library(ggplot2)
library(rgdal)
library(tidyr)
library(magrittr)

source("src/R/utils.R")
cdr = read_delim("data/CDR/sms/all-december.txt", delim = "\t",col_names = FALSE )
cdr_shape = readOGR("data/GeoJSON/CDR_join_output.geojson", "OGRGeoJSON") 

# dates = first + (1:(144*32))*hours(6)
cdr %<>% transmute(cell_id = X1, 
                        date = as.POSIXct(as.numeric(as.character(X2))/1000,origin="1970-01-01"),
                        # date =X2,
                        day = day(date),
                        sms_in = X4,
                        sms_out = X5,
                        call_in = X6,
                        call_out = X7,
                        internet = X8
)



activity_by_tower = cdr %>% group_by(day, cell_id) %>% summarise_each(funs(sum(., na.rm=TRUE)), sms_in:internet)

call_in_long = activity_by_tower %>% ungroup() %>% dplyr::select(day, call_in, cell_id) %>% 
  spread(cell_id, call_in)  %>% dplyr::select(-day)


call_in_prcomp = prcomp(call_in_long[,apply(call_in_long, 2, var, na.rm=TRUE) != 0], scale=TRUE, center=TRUE)
call_in_pca = call_in_prcomp$rotation[,1]

cdr_shape@data = cdr_shape@data %>% left_join(data.frame(call_in_pca = unname(call_in_pca), cellId = as.numeric(names(call_in_pca))), by = "cellId")


leaflet_map(cdr_shape, "call_in_pca", "Call In Variation")



cdr_shape %<>% spTransform(CRS("+proj=utm +zone=32 +datum=WGS84 +units=m"))

census = readOGR("data/GeoJSON/milano_census_ace.geojson", "OGRGeoJSON") %>%
  spTransform(CRS("+proj=utm +zone=32 +datum=WGS84 +units=m"))

#' Intersect polygons
intersection = raster::intersect(x = census, y = cdr_shape)

#' Calcualte area of each polygon
intersection@data$area = area(intersection)

#' Calculate area of each polygon
square_size = max(intersection@data$area)

#' Aggregate data into census areas summing the CDR data proportionally to the size of the squares
aggr_cdr = intersection@data %>% dplyr::select(ACE, call_in_pca, area, -cellId) %>% dplyr::group_by(ACE) %>% 
  summarise_each(funs(weighted.mean(., area,na.rm=TRUE))) %>% as.data.frame()

#' Join data to census polygons
census@data = census@data %>% left_join(aggr_cdr, by = "ACE")

leaflet_map(census, "call_in_pca", "Aggr Call In PCA")

plot(census$call_in_pca, census$deprivation)
cor(census$call_in_pca, census$deprivation)

census@data = census@data %>% mutate(high_school = P48/P1, 
                                     illiteracy = P52/P1, sixtyfive_plus = (P27 + P28 + P29)/P1,
                                     foreigners = ST15/P1,
                                     rented_dwelling = ifelse(A46 + A47+ A48 > 0, A46/(A46 + A47+ A48), NA),
                                     unemployment = P62/P60,
                                     work_force = P60/(P17 + P18 + P19 + P20 + P21 + P22 + P23 + P24 + P25 + P26 + P27 + P28 + P29))

png("/doc/plots/census_cdr_corr_2.png", height = 1000, width = 1000)
corr_plot = ggpairs(census@data %>% dplyr::select(call_in_pca, deprivation, high_school:work_force) %>%
                      mutate(log_call_in_pca = log1p(call_in_pca)))
print(corr_plot)
dev.off()
# activity = cdr %>% group_by(day) %>% summarise_each(funs(sum(., na.rm=TRUE)), sms_in:internet)

activity %>% mutate(date = dates)

ggplot(activity) + geom_line(aes(x = day, y = internet))