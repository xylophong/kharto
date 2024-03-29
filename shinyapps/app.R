library(shinydashboard)
library(shiny)
library(shinyjs)
library(DT)
library(rgdal)
library(sf)
library(leaflet)
library(tidyverse)
library(readxl)
library(knitr)

ui <- dashboardPage(
  skin="green",
  
  dashboardHeader(title = "kharto"),
  
  dashboardSidebar(
    tags$style(".skin-green .sidebar a { color: #444}"),
    uiOutput(outputId="dynamic_etablissement"),
    uiOutput(outputId="dynamic_choice"),
    uiOutput(outputId="download_report")
  ),
  
  dashboardBody(
    uiOutput(outputId="dynamic_map"),
    uiOutput(outputId="dynamic_table"),
    uiOutput(outputId="help")
  )
)

server <- function(input, output, session) {
  
  session$onSessionEnded(stopApp) #stops app when closing browser tab
  
  options(
    shiny.maxRequestSize=30*1024^2
  )
  pal <- colorNumeric("viridis", NULL, reverse=TRUE)
  
  #### INTRO ####
  
  url <- a(
    "l'onglet FOCUS de Cartographie ATIH", 
    href="https://cartographie.atih.sante.fr/#pg=3;l=fr;v=map1"
  )
  github <- a(
    "ce lien.", 
    href="https://github.com/deepPhong/kharto"
  )
  
  mail <- a(
    "dinh-phong.nguyen@aphp.fr",
    href="mailto:dinh-phong.nguyen@aphp.fr?subject=Question/bug kharto"
  )
  
  output$help <- renderUI({
    fluidRow(
      box(
        width=6,
        title = "Instructions",
        solidHeader = TRUE,
        collapsible = TRUE,
        status = "success",
        "Instructions détaillées sur", tagList(github), br(),
        HTML("<u> Résumé</u> :"), br(),
        HTML("1) Se rendre sur"), tagList(url), br(),
        HTML("2) Choisir le type de séjour"), br(),
        HTML("3) Cliquer sur <b>Voir la carte</b>"), br(),
        HTML("4) Sélectionner l'établissement"), br(),
        HTML("5) Cliquer sur <b>Mettre à jour la carte</b>"), br(),
        HTML("6) Cliquer sur <b>Imprimer/Exporter</b> en haut à droite de la carte"), br(),
        HTML("7) Cliquer sur <b>Exporter les données</b>"), br(),
        HTML("8) Importer les données dans <code>kharto</code>"),
        br(), HTML("<i>PS: Pour l'instant, seule l'île-de-France est disponible.</i>")
      ),
      box(
        width=6,
        title = "Qu'est-ce que c'est ?",
        solidHeader = TRUE,
        collapsible = TRUE,
        status = "success",
        HTML("<code>kharto</code>"), "est une application qui permet de représenter",
        "visuellement le recrutement d'un établissement hospitalier par commune.",
        "Les données à charger sont mises à disposition sur l'application de",
        "cartographie de l'ATIH (suivre les instructions pour les récupérer).",
        br(), br(), "Pour toute question ou bug :", tagList(mail)
      )
    )
  })
  
  observeEvent(ordered_table(), {
    req(ordered_table())
    output$help <- renderUI({hide("help")})
  })
  
  #### LOADING DATA ####
  
  load_map <- reactive({
    withProgress(message="Chargement du fond de carte", {
      map_path <- "correspondances-code-insee-code-postal.geojson"
      incProgress(1/3)
      map <- readOGR(map_path)
      incProgress(1/3)
    })
    return(map)
  })
  
  load_dept <- reactive({
    map_path <- "geoflar-departements.geojson"
    map <- readOGR(map_path)
    return(map)
  })
  
  load_etablissement <- reactive({
    req(input$etablissement)
    etabs = list()
    for (etab in input$etablissement$datapath) {
      etab_name <- substr(etab, (nchar(etab)+1)-10, nchar(etab))
      etabs[[etab_name]] <- read_excel(
        etab, 
        na=c("", " ", "N/A - secret statistique"), 
        skip=14,
        col_types=c("text", "text", "numeric")
      )
      colnames(etabs[[etab_name]]) <- c("postal_code", "nom_comm", "nb_patients")
      etabs[[etab_name]] <- etabs[[etab_name]][!is.na(etabs[[etab_name]]$nb_patients),]
      etabs[[etab_name]]$postal_code <- as.character(etabs[[etab_name]]$postal_code)
    }
    return(etabs)
  })
  
  etablissement_name <- reactive({
    req(input$etablissement)
    names_list <- sapply(
      input$etablissement$datapath, 
      function(x) read_excel(
          x, 
          skip = 12, 
          n_max = 1, 
          col_names = FALSE
        )[[1]]
    )
    Encoding(names_list) <- "latin1"
    return(names_list)
  })
  
  #### GENERATING TABLES ####
  
  info_on_map <- reactive({
    req(load_etablissement(), etablissement_name(), load_map())
    map <- st_as_sf(load_map()) %>%
      select(c(
        "postal_code",  
        "nom_dept1", 
        "nom_comm", 
        "population"
      )
    )
    etabs <- load_etablissement()
    etab_names <- etablissement_name()
    info_on_map <- list()
    
    for (i in seq_along(etabs)) {
      data <- etabs[[i]] %>% 
        filter(nb_patients >= 20) %>% 
        select(c(postal_code, nb_patients))
      info_on_map[[etab_names[i]]] <- sp::merge(
        map, 
        data, 
        by="postal_code",
        all.x=FALSE
      ) 
      info_on_map[[etab_names[i]]] <- (
       info_on_map[[etab_names[i]]] %>% 
         group_by(postal_code) %>% 
         top_n(1, population)
      )
    }
    return(info_on_map)
  })
  
  ordered_table <- reactive({
    req(info_on_map(), etablissement_name())
    infos <- info_on_map()
    ordered_table <- list()
    etab_names <- etablissement_name()
    
    for (i in seq_along(infos)) {
      ordered_table[[etab_names[i]]] <- (
        infos[[i]][order(-infos[[i]]$nb_patients), ] 
      ) %>% st_drop_geometry()
      
      ordered_table[[etab_names[i]]] <- ordered_table[[etab_names[i]]][
        !is.na(ordered_table[[etab_names[i]]]$nb_patients), ]
      
      colnames(ordered_table[[etab_names[i]]]) <- c(
        "Code Postal",  
        "Departement", 
        "Commune", 
        "Population", 
        "Nb Patients"
      )
      ordered_table[[etab_names[i]]]$Population <- (
        1000 * ordered_table[[etab_names[i]]]$Population
      )
    }
    return(ordered_table)
  })
  
  #### GENERATING MAPS ####
  
  rendered_maps <- reactive({
    req(info_on_map(), etablissement_name())
    rendered_maps <- list()
    infos <- info_on_map()
    etab_names <- etablissement_name()
    n <- length(etab_names)
    
    for (i in seq_along(infos)) {
      rendered_maps[[etab_names[i]]] <- leaflet(infos[[i]]) %>%
        setView(
          lat=48.86263, 
          lng=2.336293, 
          zoom=10
        ) %>%
        addProviderTiles(
          provider="Esri.WorldGrayCanvas",
          options = providerTileOptions(
            attribution='Tiles &copy; Esri &mdash; Esri, DeLorme, NAVTEQ'
          )
        ) %>%
        addPolygons(
          stroke=FALSE,
          weight=0.5,
          opacity=0.7,
          color="white",
          dashArray="3",
          smoothFactor=0.3, 
          fillOpacity=1,
          fillColor=~pal(log(nb_patients)),
          label=~paste0(
            nom_comm, ": ", formatC(nb_patients, big.mark=","))
        ) %>% 
        addPolygons(
          data=load_dept(),
          stroke=TRUE,
          fill=FALSE,
          weight=1.5,
          opacity=1,
          color="white"
        ) %>% 
        addLegend(
          pal=pal, 
          values=~log(nb_patients), 
          title="Nb Patients",
          labFormat=labelFormat(transform=function(x)round(exp(x))),
          opacity=1.0
        )
      incProgress(1/n)
    }
    return(rendered_maps)
  })
  
  #### DYNAMIC UI RENDERING ####
  
  observeEvent(load_map(), {
    output$dynamic_etablissement <- renderUI({
      req(load_map())
      fileInput(
        inputId = "etablissement", 
        label = h4("Donnees etablissements"),
        multiple = TRUE,
        buttonLabel = "Parcourir",
        placeholder = "1 ou + fichiers"
      )
    })
  })
  
  observeEvent(ordered_table(), {
    output$dynamic_map <- renderUI({
      req(ordered_table())
      fluidRow(
        box(leafletOutput("mymap"), width=12)
      )
    })
  })
  
  observeEvent(ordered_table(), {
    output$dynamic_table <- renderUI({
      req(ordered_table())
      fluidRow(
        box(dataTableOutput("etablissement_table"), width=12)
      )
    })
  })
  
  observeEvent(rendered_maps(), {
    output$dynamic_choice <- renderUI({
      req(rendered_maps())
      selectizeInput(
        inputId="etab_choice",
        label=h4("Etablissement"),
        multiple=FALSE,
        choices=names(rendered_maps())
      )
    })
  })
  
  observeEvent(input$etab_choice, {
    output$mymap <- renderLeaflet({
      req(rendered_maps(), input$etab_choice)
      withProgress(message="Production des cartes", {
        rendered_maps()[[input$etab_choice]]
      })
    })
  })
  
  observeEvent(input$etab_choice, {
    output$etablissement_table <- renderDataTable({
      req(ordered_table(), input$etab_choice)
      datatable(
        data=ordered_table()[[input$etab_choice]],
        style="bootstrap",
        rownames=FALSE,
        options=list(
          paging=TRUE,
          searching=TRUE
        )
      )
    })
  })
  
  observeEvent(ordered_table(), {
    output$download_report <- renderUI({
      div(
        style="display:inline-block;text-align: center;width: 100%;",
        downloadButton("report", "Exporter rapport")
        )
    })
  })
  
  #### GENERATING REPORTS ####
  
  output$report <- downloadHandler(
    filename = function() {
      paste(
        "rapport_", 
        iconv(input$etab_choice, to="ASCII//TRANSLIT"), 
        "_", Sys.Date(), ".html", sep=""
      )
    },
    content = function(file) {
      tempReport <- file.path(tempdir(), "report.Rmd")
      file.copy("report.Rmd", tempReport, overwrite = TRUE)
      params <- list(
        name=iconv(input$etab_choice, to="ASCII//TRANSLIT"),
        table=datatable(
          data=ordered_table()[[input$etab_choice]],
          style="bootstrap",
          rownames = FALSE,
          options=list(
            paging=TRUE,
            searching=TRUE
          )
        ),
        map = rendered_maps()[[input$etab_choice]]
      )
      rmarkdown::render(tempReport, output_file = file,
                        params = params,
                        envir = new.env(parent = globalenv())
      )
    }
  )
}

shinyApp(ui, server)