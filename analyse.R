# Défiance des ménages français envers les valeurs mobilières jugées à risque
# Sources : Eurostat (nasa_10_f_bs, nama_10_pc), INSEE (enquêtes Patrimoine), AMF (baromètre 2025)
# Lancer depuis le dossier du projet : Rscript analyse.R

suppressPackageStartupMessages({
  library(readxl); library(dplyr); library(tidyr); library(ggplot2)
  library(scales); library(sandwich); library(lmtest)
})

brut <- "donnees/brut/"
dir.create("sorties", showWarnings = FALSE)

theme_set(theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"),
        plot.caption = element_text(colour = "grey40", size = 8, hjust = 0),
        panel.grid.minor = element_blank(), legend.position = "bottom",
        plot.background = element_rect(fill = "white", colour = NA)))  # fond opaque : lisible en mode sombre
bleu <- "#1f4e79"; gris <- "grey70"

# ---------------------------------------------------------------------------
# 1. Eurostat : part des valeurs mobilières dans les actifs financiers des ménages
#    Valeurs mobilières = titres de créance (F3) + actions cotées (F511) + parts de fonds (F52)
# ---------------------------------------------------------------------------
pays_noms <- c(FR = "France", DE = "Allemagne", NL = "Pays-Bas", BE = "Belgique",
               IT = "Italie", ES = "Espagne", SE = "Suède", DK = "Danemark",
               FI = "Finlande", AT = "Autriche")

fin <- read.csv(paste0(brut, "eurostat_nasa_10_f_bs.csv")) |>
  select(geo, annee = TIME_PERIOD, item = na_item, v = OBS_VALUE) |>
  pivot_wider(names_from = item, values_from = v) |>
  mutate(part_vm      = (F3 + F511 + F52) / F,
         part_actions = F511 / F,
         part_depots  = F2 / F,
         part_assvie  = F62 / F) |>
  filter(!is.na(part_vm))

pib <- read.csv(paste0(brut, "eurostat_pib_hab.csv")) |>
  select(geo, annee = TIME_PERIOD, pib_hab = OBS_VALUE)

panel <- fin |> inner_join(pib, by = c("geo", "annee")) |>
  mutate(pays = pays_noms[geo], france = geo == "FR")

g1 <- ggplot(panel, aes(annee, part_vm, group = pays)) +
  geom_line(data = filter(panel, !france), colour = gris) +
  geom_line(data = filter(panel, france), colour = bleu, linewidth = 1.4) +
  ggrepel::geom_text_repel(data = panel |> group_by(pays) |> filter(annee == max(annee)),
            aes(label = pays, colour = france), direction = "y", hjust = 0, nudge_x = 0.6,
            size = 3, segment.colour = "grey85", show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = bleu, `FALSE` = "grey45")) +
  scale_y_continuous(labels = percent) +
  scale_x_continuous(expand = expansion(mult = c(0.01, 0.12))) +
  labs(title = "Part des valeurs mobilières dans l'épargne financière des ménages",
       subtitle = "Actions cotées + parts de fonds + obligations détenues en direct, en % des actifs financiers",
       x = NULL, y = NULL,
       caption = "Source : Eurostat, nasa_10_f_bs (F3+F511+F52)/F, ménages et ISBLSM. L'assurance-vie en unités de compte n'est pas comptée.")
ggsave("sorties/1_comparaison_europe.png", g1, width = 9, height = 5.5, dpi = 200)

# Régression : écart de la France aux autres pays, à PIB/hab et année donnés
m_fr  <- lm(part_vm ~ france + log(pib_hab) + factor(annee), data = panel)
# Erreurs robustes groupées par pays (10 pays seulement : prudence sur la significativité)
ct_fr  <- coeftest(m_fr,  vcov = vcovCL(m_fr,  cluster = ~geo))

# ---------------------------------------------------------------------------
# 2. INSEE : taux de détention de valeurs mobilières par les ménages
# ---------------------------------------------------------------------------
lire <- function(f, sh) suppressMessages(read_excel(paste0(brut, f), sheet = sh, col_names = FALSE))

h <- lire("RPM2024-F25.xlsx", "Figure 1")
stopifnot(grepl("Valeurs mobili", h[[4]][4]))
histo <- tibble(annee = as.integer(h[[1]][5:10]), taux = as.numeric(h[[4]][5:10]))

d <- lire("hvp_txdetention.xlsx", "NIVVIE")
col_vm <- grep("Valeurs mobili", unlist(d[4, ]))
stopifnot(length(col_vm) == 1)
deciles <- tibble(tranche = d[[1]][5:14], taux = as.numeric(d[[col_vm]][5:14])) |>
  mutate(decile = paste0("D", 1:10))
taux_2024 <- as.numeric(d[[col_vm]][15])
histo <- bind_rows(histo, tibble(annee = 2024L, taux = taux_2024))

crises <- tibble(annee = c(2001, 2008, 2011, 2020),
                 nom = c("Bulle internet", "Crise financière", "Crise de l'euro", "Covid"))

g2 <- ggplot(histo, aes(annee, taux / 100)) +
  geom_vline(data = crises, aes(xintercept = annee), linetype = "dashed", colour = gris) +
  geom_text(data = crises, aes(x = annee, y = 0.01, label = nom), angle = 90,
            vjust = -0.4, hjust = 0, size = 3, colour = "grey45") +
  geom_line(colour = bleu, linewidth = 1.3) + geom_point(colour = bleu, size = 2.5) +
  geom_text(aes(label = paste0(format(taux, decimal.mark = ","), " %")), vjust = -1, size = 3.3) +
  scale_y_continuous(labels = percent, limits = c(0, 0.27)) +
  labs(title = "Moins d'un ménage français sur cinq détient des valeurs mobilières",
       subtitle = "Part des ménages détenant actions, obligations ou parts de fonds hors assurance-vie",
       x = NULL, y = NULL,
       caption = "Source : INSEE, enquêtes Patrimoine 1998-2021 (France métropolitaine) ; Histoire de vie et Patrimoine 2023-2024 (France hors Mayotte).")
ggsave("sorties/2_detention_historique.png", g2, width = 9, height = 5.5, dpi = 200)

g3 <- ggplot(deciles, aes(factor(decile, levels = decile), taux / 100)) +
  geom_col(fill = bleu, width = 0.7) +
  geom_text(aes(label = paste0(format(taux, decimal.mark = ","), " %")), vjust = -0.5, size = 3.3) +
  scale_y_continuous(labels = percent, limits = c(0, 0.55)) +
  labs(title = "Même parmi les 10 % les plus aisés, plus de la moitié n'en détient pas",
       subtitle = "Taux de détention de valeurs mobilières par décile de niveau de vie, début 2024",
       x = "Décile de niveau de vie (D1 = 10 % les plus modestes)", y = NULL,
       caption = "Source : INSEE, enquête Histoire de vie et Patrimoine 2023-2024.")
ggsave("sorties/3_detention_deciles.png", g3, width = 9, height = 5.5, dpi = 200)

# ---------------------------------------------------------------------------
# 3. AMF : perception du risque
# ---------------------------------------------------------------------------
amf <- read.csv("donnees/amf_barometre.csv")

g4 <- amf |> select(annee, `Refusent tout risque` = refuse_tout_risque,
                    `Intéressés par les actions` = interet_actions) |>
  pivot_longer(-annee) |>
  ggplot(aes(annee, value / 100, colour = name)) +
  geom_line(linewidth = 1.3) + geom_point(size = 2.5) +
  geom_text(aes(label = paste0(value, " %")), vjust = -1, size = 3, show.legend = FALSE) +
  scale_colour_manual(values = c(bleu, "#c0504d"), name = NULL) +
  scale_y_continuous(labels = percent, limits = c(0, 0.62)) +
  scale_x_continuous(breaks = amf$annee) +
  labs(title = "Le refus du risque recule, mais reste la première attitude",
       subtitle = "Part des Français de 18 ans et plus",
       x = NULL, y = NULL,
       caption = "Source : AMF, Baromètre de l'épargne et de l'investissement 2025 (Audirep, n = 2 120), p. 41-42.")
ggsave("sorties/4_amf_risque.png", g4, width = 9, height = 5.5, dpi = 200)

# ---------------------------------------------------------------------------
# 4. Mémoire des crises
#  a) Participation : les cours ont rattrapé leurs pertes, le taux de détention non
#  b) Flux (transactions, non contaminés par les cours) vs rendement des 3 années précédentes,
#     séparément pour les actions cotées détenues en direct (F511) et les parts de fonds (F52)
# ---------------------------------------------------------------------------
cours <- read.csv(paste0(brut, "ocde_cours_actions_fr.csv")) |>
  transmute(date = as.Date(observation_date), indice = SPASTT01FRM661N) |>
  filter(format(date, "%m") == "12") |>
  transmute(annee = as.integer(format(date, "%Y")), indice, rdt = indice / lag(indice) - 1)

base98 <- cours$indice[cours$annee == 1998]
duo <- bind_rows(
  cours |> filter(annee >= 1996) |>
    transmute(annee, valeur = 100 * indice / base98, serie = "Cours des actions françaises (base 100 = 1998)"),
  histo |> transmute(annee, valeur = taux, serie = "Ménages détenant des valeurs mobilières (%)")) |>
  mutate(serie = factor(serie, levels = unique(serie)))

g5 <- ggplot(duo, aes(annee, valeur)) +
  geom_vline(data = crises, aes(xintercept = annee), linetype = "dashed", colour = gris) +
  geom_line(colour = bleu, linewidth = 1.2) +
  geom_point(data = filter(duo, grepl("%", serie)), colour = bleu, size = 2.3) +
  facet_wrap(~serie, ncol = 1, scales = "free_y") +
  scale_y_continuous(limits = c(0, NA)) +
  theme(strip.text = element_text(face = "bold", hjust = 0, size = 11)) +
  labs(title = "La Bourse a effacé ses crises, les épargnants ne sont pas revenus",
       subtitle = "Pointillés : bulle internet (2001), crise financière (2008), crise de l'euro (2011), Covid (2020)",
       x = NULL, y = NULL,
       caption = "Sources : OCDE via FRED (SPASTT01FRM661N, valeur de décembre) ; INSEE, enquêtes Patrimoine 1998-2024.")
ggsave("sorties/5_cours_vs_detention.png", g5, width = 9, height = 6.5, dpi = 200)

flux <- read.csv(paste0(brut, "eurostat_flux_fr.csv")) |>
  select(annee = TIME_PERIOD, item = na_item, v = OBS_VALUE) |>
  pivot_wider(names_from = item, values_from = v) |>
  left_join(fin |> filter(geo == "FR") |> transmute(annee = annee + 1, encours_prec = F), by = "annee") |>
  left_join(cours, by = "annee") |> arrange(annee) |>
  mutate(actions_direct = F511 / encours_prec,      # achats nets, en % des actifs financiers N-1
         fonds          = F52 / encours_prec,
         rdt_passe_3a   = (lag(rdt) + lag(rdt, 2) + lag(rdt, 3)) / 3) |>
  filter(!is.na(rdt_passe_3a), !is.na(actions_direct))

tests_flux <- lapply(c("actions_direct", "fonds"), function(y) {
  m <- lm(reformulate("rdt_passe_3a", y), data = flux)
  ct <- coeftest(m, vcov = NeweyWest(m, lag = 2, prewhite = FALSE))
  r   <- cor(flux[[y]], flux$rdt_passe_3a)
  adf <- suppressWarnings(tseries::adf.test(flux[[y]])$p.value)
  tibble(serie = y, correlation = r, coef = ct[2, 1], p_newey_west = ct[2, 4], adf_p = adf, n = nobs(m))
}) |> bind_rows()

# Participation vs rendement moyen des 10 années précédentes (7 points : indicatif seulement)
histo_r10 <- histo |> rowwise() |>
  mutate(rdt_10a = mean(cours$rdt[cours$annee < annee & cours$annee >= annee - 10])) |> ungroup()
cor_part <- cor.test(histo_r10$taux, histo_r10$rdt_10a)

# ---------------------------------------------------------------------------
# 5. Résumé chiffré
# ---------------------------------------------------------------------------
dern <- max(panel$annee)
classement <- panel |> filter(annee == dern) |> arrange(desc(part_vm)) |>
  transmute(pays, part_vm = round(100 * part_vm, 1), part_depots = round(100 * part_depots, 1),
            part_assvie = round(100 * part_assvie, 1))

sink("sorties/resultats.txt")
cat("== Part des valeurs mobilières dans les actifs financiers des ménages,", dern, "(%) ==\n")
print(classement, row.names = FALSE)
cat("\n== Régression 1 : part_vm ~ France + log(PIB/hab) + effets année (erreurs groupées par pays) ==\n")
print(ct_fr[1:3, ])
cat("\nN =", nobs(m_fr), "observations pays-année,", n_distinct(panel$geo), "pays,",
    min(panel$annee), "-", dern, "\n")
cat("\n== Mémoire des crises (a) : taux de détention vs rendement moyen des 10 années précédentes ==\n")
print(histo_r10, n = Inf)
cat("Corrélation :", round(cor_part$estimate, 2), "| p =", round(cor_part$p.value, 3), "| n = 7 : indicatif\n")
cat("\n== Mémoire des crises (b) : achats nets ~ rendement moyen des 3 années précédentes (Newey-West, 2 retards) ==\n")
print(as.data.frame(tests_flux |> mutate(across(where(is.double), ~ round(.x, 3)))))
cat("\n== INSEE : taux de détention de valeurs mobilières (%) ==\n"); print(histo, n = Inf)
cat("\n== INSEE : par décile de niveau de vie, 2024 (%) ==\n"); print(deciles[, c("decile", "taux")], n = Inf)
cat("\n== AMF ==\n"); print(amf)
sink()

cat(readLines("sorties/resultats.txt"), sep = "\n")
