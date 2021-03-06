#' Prepare outputs for REMIND: Set correct tech names, CES node names and years.
#'
#' @param demByTech the share of FEs for different REMIND CES nodes.
#' @param intensity the energy intensity of the REMIND CES nodes wrt. the FE carriers
#' @param capCost levelized capital costs of REMIND CES nodes
#' @param EDGE2teESmap map EDGE-T technologies to REMIND ES techs
#' @param REMINDtall the full REMIND timestep range as required for input data
#' @param REMIND2ISO_MAPPING map REMIND regions to ISO3 country codes
#' @import data.table
#' @importFrom rmndt approx_dt
#' @export

prepare4REMIND <- function(demByTech, intensity, capCost,
                           EDGE2teESmap,
                           REMINDtall,
                           REMIND2ISO_MAPPING=NULL){
    value <- NULL

    ## define regional aggregation
    if (!is.null(REMIND2ISO_MAPPING)) {
      regcol = "region"
    } else { regcol = "iso"}

    ## load conversion factor
    EJ_2_Twa <- 31.71e-03 ## TWa is the unit expected in REMIND for the final energy values
    conv_2005USD_1990USD=0.67 ## 2005USD=0.67*1990USD
    ## energy intensity
    intensity=merge(intensity, EDGE2teESmap[,c("CES_node","teEs")],
                    by="CES_node",all.x=TRUE)
    intensity=intensity[, c("year", regcol, "teEs", "value"),with = F]
    setnames(intensity, old = c("year", "teEs"), new = c("tall", "all_teEs"))
    intensity=approx_dt(dt=intensity, xdata=REMINDtall,
                        xcol="tall", ycol="value",
                        idxcols=c(regcol, "all_teEs"),
                        extrapolate=T)
    intensity[,value:=value ## in [milliokm/EJ]
              /EJ_2_Twa     ## in [millionkm/Twa]
              *1e-6         ## in [trillionkm/Twa]
              ]
    setcolorder(intensity, c("tall", regcol, "all_teEs", "value"))

    ## non-fuel price
    budget=merge(capCost, unique(EDGE2teESmap[,c("teEs","EDGE_top")]),
                 by="teEs",all.x=TRUE)
    budget=budget[, c("year", regcol, "teEs", "value"),with = F]
    setnames(budget, old = c("year", "teEs"), new = c("tall", "all_teEs"))

    budget=approx_dt(dt=budget, xdata=REMINDtall,
                     xcol="tall", ycol="value",
                     idxcols=c(regcol, "all_teEs"),
                     extrapolate=T)

    budget[,value:=value ## in 1990USD/pkm
                   /conv_2005USD_1990USD] ## in [2005USD/pkm]
    setcolorder(budget, c("tall", regcol, "all_teEs", "value"))

    ## demand by technology
    demByTech=merge(demByTech, EDGE2teESmap[,c("CES_node","all_in","all_enty","teEs")],
                by="CES_node", all.x=TRUE)
    demByTech=demByTech[, c("year", regcol, "all_enty", "all_in", "teEs", "value"),with = F]
    setnames(demByTech, old = c("year", "teEs"), new = c("tall", "all_teEs"))
    demByTech <- approx_dt(dt=demByTech, xdata=REMINDtall,
                        xcol="tall", ycol="value",
                        idxcols=c(regcol,"all_in","all_enty","all_teEs"),
                        extrapolate=T)[, value := EJ_2_Twa * value] ## in TWa
    setcolorder(demByTech, c("tall", regcol,"all_enty","all_in","all_teEs","value"))

    if (!is.null(REMIND2ISO_MAPPING)) {
      ## REMIND expects region column as "all_regi"
      for (dt in c("demByTech", "intensity", "budget")) {
        setnames(get(dt), old = regcol, new = "all_regi")
      }
    }

    result=list(demByTech=demByTech,
                intensity=intensity,
                capCost=budget)
    return(result)

}
