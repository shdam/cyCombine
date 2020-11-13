
#' Run analysis of a batch correction
#'
#' This function only runs under the assumption that the batch correction has been run with the cyCombine workflow in mind.
#'   Some result preparation can be necessary, if cyCombine was not used during batch correction.
#'   This function assumes that the uncorrected data us stored under the name "{data_dir}/{tool}_{data}_preprocessed.RDS" and
#'   the corrected data is stored with the name "{data_dir}/{tool}_{data}_corrected.RDS".
#'   The analysis currently encompass marker-wise density plots, UMAP of corrected vs uncorrected, and Earth Movers Distance.
#'
#' @param tool The name of the tool used to batch correct
#' @param data The name of the data used
#' @param data_dir The location of the preprocessed and corrected data
#' @param variant Optional: A parameter to set a variant name of an experiment
#' @param restart If TRUE, the SOM grid will be calculated even if it has been computed and stored previously
#' @param md Optional: Metadata filename. Currently not useful
#' @param panel Optional: If given, it will be used to define markers. Otherwise the function \code{\link{get_markers}} will be used
#' @param markers Optional: Manually define markers to use in plots and performance metrics
#' @param celltype_col Optional: If the cell types are know, specify which column they are defined in
#' @param segment Optional: Run only a specific segment of the analysis. Options include: "emd", "density", "umap"
#' @param gridsize The gridsize to use when clustering. Only used if no celltype_col is given
#' @param seed The seed to use when creating the UMAP
#'
#' @examples
#' run_analysis(tool = "cycombine",
#' data = "FR-FCM-ZY34",
#' data_dir = "_data")
#' run_analysis(tool = "cycombine",
#' data = "FR-FCM-ZY34",
#' data_dir = "_data",
#' variant = "_p3",
#' panel = "/attachments/MC_panel3.xlsx")
#' @export
run_analysis <- function(tool,
                         data,
                         data_dir,
                         variant = NULL,
                         restart = FALSE,
                         md = NULL,
                         panel = NULL,
                         markers = NULL,
                         celltype_col = NULL,
                         segment = "",
                         gridsize = 8,
                         seed = 473){


  # Load metadata
  if(!is.null(md)){
    if(endsWith(md, "csv")){
      md <- str_c(data_dir, "/", md) %>%
        read_csv()
    } else{
      md <- str_c(data_dir, "/", md) %>%
        readxl::read_xlsx()
    }
  }
  # Load panel
  if(!is.null(panel)){
    if(endsWith(panel, "csv")){
      panel <- str_c(data_dir, "/", panel) %>%
        read_csv()
    } else{
      panel <- str_c(data_dir, "/", panel) %>%
        readxl::read_xlsx()
    }
  }

  # dir + project
  project <- paste0(tool, "_", data, variant)
  projdir <- paste0(data_dir, "/", project)

  message("Loading data..")
  # Load data
  preprocessed <- readRDS(paste0(data_dir, "/cycombine_", data, "_preprocessed.RDS"))
  corrected <- readRDS(paste0(projdir, "_corrected.RDS"))


  # Get markers
  if(is.null(markers)){
    if(is.null(panel)){
      markers <- get_markers(corrected)
    } else{
      markers <- panel %>%
        filter(marker_class %!in% c("none", "state")) %>%
        pull(antigen) %>%
        str_remove("[ _-]")
    }
  }


  if(segment %in% c("", "emd")){

    if(is.null(celltype_col)){
      # Cluster and add labels
      if (file.exists(paste0(projdir, "_som.RDS")) & !restart){
        message("Loading SOMgrid..")
        som_ <- readRDS(paste0(projdir, "_som.RDS"))
      }else{
        som_ <- corrected %>%
          create_som(seed = seed,
                     xdim = gridsize,
                     ydim = gridsize)
        saveRDS(som_, file = paste0(projdir, "_som.RDS"))
      }
      # Add labels
      corrected <- corrected %>%
        dplyr::mutate(label = som_$unit.classif)
    } else{
      # Add labels
      corrected$label <- corrected[[celltype_col]]
    }
    message("Adding labels to data..")


    preprocessed <- corrected %>%
      dplyr::select(id, label) %>%
      dplyr::left_join(preprocessed, by = "id")
  }



  # Plotting ----
  if (!dir.exists("figs")){
    dir.create("figs")
  }
  if(segment %in% c("", "density")){

    message("Creating density plots..")
    # Density plots
    suppressMessages(
      plot_density(uncorrected = preprocessed,
                   corrected = corrected,
                   markers = markers,
                   filename = paste0("figs/", project, "_densities_withcovar.png"))
    )
  }
  # suppressMessages(
  # plot_density(uncorrected = preprocessed,
  #              corrected = corrected,
  #              markers = markers,
  #              filename = paste0("figs/", project, "_densities_withcovar_label.png"),
  #              y = "label")
  # )
  # UMAP
  if(segment %in% c("", "umap")){
    message("Creating UMAPs..")
    # Down-sample
    set.seed(seed)
    preprocessed_sliced <- preprocessed %>%
      slice_sample(n = 20000)

    corrected_sliced <- corrected %>%
      semi_join(preprocessed_sliced, by = "id")

    # UMAP plot uncorrected
    umap1 <- preprocessed_sliced %>%
      plot_dimred(name = "uncorrected", type = "umap")

    # UMAP plot corrected
    umap2 <- corrected_sliced %>%
      plot_dimred(name = "corrected", type = "umap")

    plot_save_two(umap1, umap2, filename = paste0("figs/", project, "_umap.png"))
  }

  # Evaluate ----
  if(segment %in% c("", "emd")){
    message("Evaluating Earth Movers Distance..")
    emd_val <- preprocessed %>%
      cyCombine::evaluate_emd(corrected)

    message("Saving results..")
    ggsave(filename = paste0("figs/", project, "_emd.png"),
           plot = emd_val$plot, device = "png")
    saveRDS(emd_val, file = paste0(projdir, "_emd.RDS"))
  }

  message("Done!")
}