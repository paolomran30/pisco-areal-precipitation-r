# ============================================================
# AREAL PISCO - versión simple y publicable
# Promedio areal diario y mensual de precipitación PISCOp
# Autor: Paolo Silva Moran
# ============================================================

rm(list = ls())
options(stringsAsFactors = FALSE, scipen = 999)

# ------------------------------------------------------------
# 0) CONFIGURACIÓN
# ------------------------------------------------------------

setwd("C:/codigo/1. Areal PISCO")

nc_file   <- "PISCOp_d.nc"
  shp_layer <- "Tayacaja_prov"   # nombre del shapefile sin .shp

id_candidates <- c("ID_UH", "UD_H", "OBJECTID", "Name", "NOMBRE", "CODIGO")

fecha_ini <- as.Date("1981-01-01")
fecha_fin <- as.Date("2025-12-31")
fechas <- seq(fecha_ini, fecha_fin, by = "day")

dias_panel <- 12
uh_plot <- 1              # UH que se graficará en la serie diaria y mensual
buffer_celdas <- 2        # expansión visual del bbox


# ------------------------------------------------------------
# 1) PAQUETES
# ------------------------------------------------------------

library(ncdf4)
library(raster)
library(sf)
library(sp)
library(viridisLite)
library(exactextractr)


# ------------------------------------------------------------
# 2) FUNCIONES AUXILIARES
# ------------------------------------------------------------

get_id_field <- function(sf_obj, candidates) {
  hit <- candidates[candidates %in% names(sf_obj)]
  if (length(hit) > 0) hit[1] else names(sf_obj)[1]
}

safe_name <- function(x) {
  x <- as.character(x)
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- gsub("[^A-Za-z0-9_-]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x[x == "" | is.na(x)] <- "sin_id"
  make.unique(paste0("UH_", x), sep = "_")
}

sum_na <- function(x) {
  if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
}

expand_extent <- function(ext, rx, ry, n = 2) {
  extent(
    xmin(ext) - n * rx,
    xmax(ext) + n * rx,
    ymin(ext) - n * ry,
    ymax(ext) + n * ry
  )
}

deg_label_x <- function(x) {
  paste0(abs(round(x, 1)), "°", ifelse(x < 0, "W", "E"))
}

deg_label_y <- function(y) {
  paste0(abs(round(y, 1)), "°", ifelse(y < 0, "S", "N"))
}


# ------------------------------------------------------------
# 3) LECTURA DE PISCO
# ------------------------------------------------------------

pisco <- brick(nc_file)

if (is.na(crs(pisco))) {
  crs(pisco) <- CRS("+proj=longlat +datum=WGS84 +no_defs")
}

cat("Capas PISCO:", nlayers(pisco), "\n")
cat("Fechas esperadas:", length(fechas), "\n")

if (nlayers(pisco) != length(fechas)) {
  stop(
    "El número de capas del NetCDF no coincide con el rango 1981-01-01 a 2025-12-31.\n",
    "Capas NetCDF: ", nlayers(pisco), "\n",
    "Fechas esperadas: ", length(fechas)
  )
}

names(pisco) <- paste0("P_", format(fechas, "%Y%m%d"))


# ------------------------------------------------------------
# 4) LECTURA DE CUENCA / UH
# ------------------------------------------------------------

cuenca_sf <- st_read(dsn = ".", layer = shp_layer, quiet = TRUE) |>
  st_make_valid() |>
  st_zm(drop = TRUE, what = "ZM")

cuenca_sf <- cuenca_sf[!st_is_empty(cuenca_sf), ]

if (is.na(st_crs(cuenca_sf))) {
  stop("El shapefile no tiene CRS definido. Revisa el .prj antes de continuar.")
}

cuenca_sf <- st_transform(cuenca_sf, crs = crs(pisco)@projargs)

id_field <- get_id_field(cuenca_sf, id_candidates)

uh_id <- as.character(cuenca_sf[[id_field]])
uh_id[is.na(uh_id) | uh_id == ""] <- paste0("sin_id_", seq_len(sum(is.na(uh_id) | uh_id == "")))

uh_col <- safe_name(uh_id)

cuenca_sp <- as(cuenca_sf, "Spatial")

cat("Campo ID usado:", id_field, "\n")
cat("UH encontradas:", paste(uh_id, collapse = ", "), "\n")


# ------------------------------------------------------------
# 5) RECORTE PARA CÁLCULO Y VISUALIZACIÓN
# ------------------------------------------------------------

rx <- res(pisco)[1]
ry <- res(pisco)[2]

ext0 <- extent(cuenca_sp)

# Raster recortado para acelerar el cálculo
ext_calc <- expand_extent(ext0, rx, ry, n = 1)
pisco_crop <- crop(pisco, ext_calc, snap = "out")

# Raster recortado para visualización
ext_plot <- expand_extent(ext0, rx, ry, n = buffer_celdas)
pisco_plot <- crop(pisco, ext_plot, snap = "out")
pisco_plot <- extend(pisco_plot, ext_plot, value = NA)


# ------------------------------------------------------------
# 6) FIGURA 1: PANEL DE PRECIPITACIÓN DIARIA
# ------------------------------------------------------------

nshow <- min(dias_panel, nlayers(pisco_plot))

panel <- pisco_plot[[1:nshow]]
names(panel) <- paste0("Día ", 1:nshow)

rng <- range(values(panel), na.rm = TRUE)
at <- seq(rng[1], rng[2], length.out = 101)

cuenca_lines <- as(cuenca_sp, "SpatialLines")

x_ticks <- pretty(c(xmin(ext_plot), xmax(ext_plot)), n = 3)
y_ticks <- pretty(c(ymin(ext_plot), ymax(ext_plot)), n = 3)

spplot(
  panel,
  main = list(
    label = "Precipitación diaria PISCOp - primeros 12 días",
    cex = 1.1
  ),
  col.regions = viridis(100),
  at = at,
  useRaster = TRUE,
  alpha.regions = 0.98,
  scales = list(
    draw = TRUE,
    alternating = FALSE,
    x = list(
      at = x_ticks,
      labels = deg_label_x(x_ticks),
      cex = 0.55
    ),
    y = list(
      at = y_ticks,
      labels = deg_label_y(y_ticks),
      cex = 0.55
    )
  ),
  par.settings = list(
    par.strip.text = list(cex = 0.85),
    axis.text = list(cex = 0.65)
  ),
  sp.layout = list(
    list("sp.lines", cuenca_lines, col = "white", lwd = 2.3)
  ),
  as.table = TRUE,
  layout = c(4, 3)
)


# ------------------------------------------------------------
# 7) FIGURA 2: CELDAS CONSIDERADAS POR INTERSECCIÓN
# ------------------------------------------------------------

grid_tmpl <- raster(pisco_plot[[1]])
values(grid_tmpl) <- 1:ncell(grid_tmpl)

grid_polys <- rasterToPolygons(grid_tmpl, dissolve = FALSE)

# Color definido para diferenciarse claramente del borde negro
pal <- rep("dodgerblue3", length(uh_id))

plot(
  grid_polys,
  border = "grey85",
  col = NA,
  axes = FALSE,
  box = FALSE,
  main = paste0("Celdas consideradas por ", id_field)
)

for (i in seq_along(uh_id)) {
  cover_i <- rasterize(cuenca_sp[i, ], grid_tmpl, getCover = TRUE)
  used_i <- which(!is.na(values(cover_i)) & values(cover_i) > 0)
  
  if (length(used_i) > 0) {
    flag <- setValues(raster(grid_tmpl), NA)
    flag[used_i] <- 1
    
    rp <- rasterToPolygons(
      flag,
      fun = function(x) !is.na(x),
      dissolve = FALSE
    )
    
    plot(rp, add = TRUE, border = pal[i], lwd = 2.3, col = NA)
  }
}

plot(cuenca_sp, add = TRUE, border = "black", lwd = 2.4)

legend(
  "topright",
  legend = uh_id,
  col = pal,
  lwd = 2.3,
  bg = "white",
  cex = 0.85,
  title = id_field
)


# ------------------------------------------------------------
# 8) FIGURA 3: FRACCIONES DE CELDA DENTRO DE LA CUENCA
# ------------------------------------------------------------

grid_sf <- st_as_sf(grid_polys)

cu_union <- st_union(cuenca_sf)

hits <- lengths(st_intersects(grid_sf, cu_union)) > 0
grid_hit <- grid_sf[hits, ]

cu_id <- cuenca_sf[, id_field, drop = FALSE]

grid_clip <- suppressWarnings(
  st_intersection(
    st_make_valid(grid_hit),
    st_make_valid(cu_id)
  )
)

cols <- pal[match(as.character(grid_clip[[id_field]]), uh_id)]
cols[is.na(cols)] <- "dodgerblue3"

plot(
  st_geometry(grid_clip),
  border = cols,
  col = NA,
  lwd = 2.3,
  axes = FALSE,
  main = "Fracciones de celda usadas en el promedio areal"
)

plot(cuenca_sp, add = TRUE, border = "black", lwd = 2.4)

legend(
  "topright",
  legend = uh_id,
  col = pal,
  lwd = 2.3,
  bg = "white",
  cex = 0.85,
  title = id_field
)


# ------------------------------------------------------------
# 9) PROMEDIO AREAL PONDERADO
# ------------------------------------------------------------

# Área real de cada celda en km².
# Como PISCO está en lat/lon, este peso mejora el promedio areal.
area_celda <- area(pisco_crop[[1]])

pp_areal <- exact_extract(
  pisco_crop,
  cuenca_sf,
  "weighted_mean",
  weights = area_celda,
  progress = TRUE
)

pp_areal <- as.data.frame(pp_areal, check.names = FALSE)

rownames(pp_areal) <- uh_col
colnames(pp_areal) <- names(pisco_crop)

daily <- data.frame(
  Fecha = fechas,
  t(as.matrix(pp_areal)),
  check.names = FALSE
)

names(daily)[-1] <- uh_col


# ------------------------------------------------------------
# 10) SERIE MENSUAL
# ------------------------------------------------------------

daily$YearMonth <- format(daily$Fecha, "%Y-%m")

monthly <- aggregate(
  daily[, uh_col, drop = FALSE],
  by = list(YearMonth = daily$YearMonth),
  FUN = sum_na
)

monthly$Fecha <- as.Date(paste0(monthly$YearMonth, "-01"))

monthly <- monthly[, c("Fecha", "YearMonth", uh_col)]


# ------------------------------------------------------------
# 11) FIGURA 4: SERIE DIARIA
# ------------------------------------------------------------

uh_plot <- min(uh_plot, length(uh_col))

y_daily <- daily[[uh_col[uh_plot]]]

plot(
  daily$Fecha,
  y_daily,
  type = "l",
  col = "blue",
  lwd = 0.5,
  xlab = "Fecha",
  ylab = "Precipitación diaria [mm/día]",
  main = paste0("Precipitación media areal diaria - ", uh_id[uh_plot])
)

grid()


# ------------------------------------------------------------
# 12) FIGURA 5: SERIE MENSUAL
# ------------------------------------------------------------

y_monthly <- monthly[[uh_col[uh_plot]]]

plot(
  monthly$Fecha,
  y_monthly,
  type = "l",
  col = "blue",
  lwd = 0.8,
  xlab = "Fecha",
  ylab = "Precipitación mensual [mm/mes]",
  main = paste0("Precipitación media areal mensual - ", uh_id[uh_plot])
)

grid()


# ------------------------------------------------------------
# 13) EXPORTACIÓN SIMPLE
# ------------------------------------------------------------

# Se elimina la columna auxiliar YearMonth del diario antes de exportar
write.csv(
  daily[, c("Fecha", uh_col)],
  "pp_tayacaja_diaria_areal_PISCO.csv",
  row.names = FALSE
)

write.csv(
  monthly[, c("Fecha", "YearMonth", uh_col)],
  "pp_tayacaja_mensual_areal_PISCO.csv",
  row.names = FALSE
)

cat("\nListo.\n")
cat("CSV diario generado: precipitacion_diaria_areal_PISCO.csv\n")
cat("CSV mensual generado: precipitacion_mensual_areal_PISCO.csv\n")