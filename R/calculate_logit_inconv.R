#' Calculate logit level shares based on inconvenience costs (instead of share weights)
#'
#' @param prices logit prices
#' @param vot_data value-of-time data
#' @param inco_data inconvenience cost data
#' @param logit_params contains logit exponents
#' @param intensity_data logit level intensity data
#' @param price_nonmot price of non-motorized modes in the logit tree
#' @import data.table
#' @export

calculate_logitinconv <- function(prices,
                            vot_data,
                            inco_data,
                            logit_params,
                            intensity_data,
                            price_nonmot) {

  tot_price <- non_fuel_price <- subsector_L3 <- logit.exponent <- share <- pinco <- NULL
  time_price <- `.` <- fuel_price_pkm <- tot_VOT_price <- MJ_km <- EJ_Mpkm_final <- NULL
  iso <- technology <- vehicle_type <- subsector_L1 <- NULL
  
  
  ## X2Xcalc is used to traverse the logit tree, calculating shares and intensities
  X2Xcalc <- function(prices, mj_km_data, level_base, level_next, group_value) {
    final_inco <- inco_data[[paste0(level_next, "_final_inconv")]]
    logit_exponent <- logit_params[[paste0("logit_exponent_", level_next)]]

    ## data contains all the prices in the beginning
    all_subsectors <- c("technology", "vehicle_type", "subsector_L1", "subsector_L2",
                        "subsector_L3", "sector")
    ## takes the right files using the names as inputs
    value_time <- vot_data[[paste0("value_time_", level_next)]]
    ## joins the df containing the prices with the df containing the logit exponents
    df <- merge(prices, logit_exponent,
                by=intersect(names(prices), names(logit_exponent)), all.x = TRUE)

    ## joins the previous df with gathe df containing the inconvenience costs
    df <- merge(df, final_inco, by=intersect( names(df),names(final_inco)), all.y=TRUE)
    ## delete entries have tot_price NA (e.g. 1900 BEV)
    df <- df[ !(is.na(tot_price))]
    ## entries that are not present in the mix have non_fuel_price == 0, but also Walk and Cycle: delete all the not-present in the mix options
    df <- df[(non_fuel_price>0)|(non_fuel_price==0 & subsector_L3 %in% c("Walk", "Cycle"))]
    ## needs random lambdas for the sectors that are not explicitly calculated
    df <- df[ is.na(logit.exponent), logit.exponent := -10]

    ## calculate the shares given prices, lambda and pinco
    df <- df[, share := (tot_price+pinco)^logit.exponent/(sum((tot_price+pinco)^logit.exponent)),
             by = c(group_value, "iso", "year")]

    ## filter out NaNs that appear when there are no choices in the nest
    df <- df[ !is.nan(share),]

    ## merge value of time for the selected level and assign 0 to the entries that don't have it
    df <- merge(df, value_time, by=intersect(names(df),names(value_time)), all.x=TRUE)

    df <- df[is.na(time_price), time_price := 0]
    df <- df[, tot_VOT_price := time_price + tot_VOT_price]
    df <- df[, tot_price := tot_price + time_price]

    MJ_km <- merge(df, mj_km_data, by=intersect(names(df),names(mj_km_data)),all = FALSE)

    MJ_km <- MJ_km[, .(MJ_km = sum(share * MJ_km)),
                   by = c("iso", "year", "technology", group_value)]

    ## get rid of the ( misleading afterwards) columns
    df_shares <- copy(df)

    df_shares <- df_shares[
      , c("share", "iso", "year",
          all_subsectors[
            seq(match(group_value, all_subsectors) - 1,
                length(all_subsectors), 1)],
          "tot_VOT_price",
          "fuel_price_pkm",
          "non_fuel_price",
          "tot_price"), with = FALSE]

    ## calculate 'one level up' database with the useful columns only
    df <- df[
      , c("share","tot_price","tot_VOT_price",
          "fuel_price_pkm","non_fuel_price","iso","year",
          all_subsectors[
            seq(match(group_value, all_subsectors) - 1,
                length(all_subsectors), 1)]), with = FALSE]

    ## calculate prices of one level up
    df=df[,.(tot_price=sum(share*tot_price),
             tot_VOT_price=sum(share*tot_VOT_price),
             fuel_price_pkm=sum(share*fuel_price_pkm),
             non_fuel_price=sum(share*non_fuel_price)),
          by = c("iso","year",
                 all_subsectors[
                   seq(match(group_value,all_subsectors),
                       length(all_subsectors),1)])]

    return(list(df, MJ_km, df_shares))

  }


  ## FV merge non-motorized prices with value of time (~technology price for non-motorized)

  ## non-fuel prices
  base <- merge(prices, price_nonmot, all = TRUE,
                by = c("tot_price","iso","year",
                       "technology","vehicle_type",
                       "subsector_L1","subsector_L2","subsector_L3","sector"))

  base[,tot_VOT_price := 0]
  #Cycling and Walking have no fuel and non fuel prices, 0 instead of NA is given
  base[is.na(fuel_price_pkm), fuel_price_pkm := 0]
  base[is.na(non_fuel_price), non_fuel_price := 0]

  ## energy intensity
  mj_km_data <- intensity_data[, MJ_km := EJ_Mpkm_final
                               * 1e12 # to MJ
                               * 1e-6 # MJ/km
                               ]
  mj_km_data <- mj_km_data[,-"EJ_Mpkm_final"]

  FV_all <- X2Xcalc(base, mj_km_data,
                    level_base = "base",
                    level_next = "FV",
                    group_value = "vehicle_type")

  FV <- FV_all[[1]]
  MJ_km_FV <- FV_all[[2]]
  FV_shares <- FV_all[[3]][,.(share, iso, year, technology, vehicle_type, subsector_L1)]

  # VS1
  VS1_all <- X2Xcalc(FV, MJ_km_FV,
                     level_base = "FV",
                     level_next = "VS1",
                     group_value = "subsector_L1")

  VS1 <- VS1_all[[1]]
  MJ_km_VS1 <- VS1_all[[2]]
  VS1_shares <- VS1_all[[3]][,.(share, iso, year, vehicle_type, subsector_L1)]

  # S1S2
  S1S2_all <- X2Xcalc(VS1, MJ_km_VS1,
                      level_base = "VS1",
                      level_next = "S1S2",
                      group_value = "subsector_L2")

  S1S2 <- S1S2_all[[1]]
  MJ_km_S1S2 <- S1S2_all[[2]]
  S1S2_shares <- S1S2_all[[3]]


  # S2S3
  S2S3_all <- X2Xcalc(S1S2, MJ_km_S1S2,
                      level_base = "S1S2",
                      level_next = "S2S3",
                      group_value = "subsector_L3")

  S2S3 <- S2S3_all[[1]]
  MJ_km_S2S3 <- S2S3_all[[2]]
  S2S3_shares <- S2S3_all[[3]]

  # S3S
  S3S_all <- X2Xcalc(S2S3, MJ_km_S2S3,
                     level_base = "S2S3",
                     level_next = "S3S",
                     group_value = "sector")
  S3S <- S3S_all[[1]]
  MJ_km_S3S <- S3S_all[[2]]
  S3S_shares <- S3S_all[[3]]

  share_list=list(S3S_shares=S3S_shares,
                  S2S3_shares=S2S3_shares,
                  S1S2_shares=S1S2_shares,
                  VS1_shares=VS1_shares,
                  FV_shares=FV_shares)

  prices_list=list(S3S=S3S,
                   S2S3=S2S3,
                   S1S2=S1S2,
                   VS1=VS1,
                   FV=FV,
                   base=base)

  result=list(mj_km_data=mj_km_data,
              prices_list=prices_list,
              share_list=share_list)

  return(result)
}
