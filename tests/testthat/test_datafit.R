context("datafit")
suppressWarnings(RNGversion("3.5.0"))


# tests for data based estimates (no actual reference model)

if (!requireNamespace("glmnet", quietly = TRUE)) {
  stop("glmnet needed for this function to work. Please install it.",
    call. = FALSE
  )
}

set.seed(1235)
n <- 40
nterms <- 5
x <- matrix(rnorm(n * nterms, 0, 1), n, nterms)
b <- runif(nterms) - 0.5
dis <- runif(1, 1, 2)
weights <- sample(1:4, n, replace = TRUE)
offset <- rnorm(n)
chains <- 2
seed <- 1235
iter <- 500
source(file.path("helpers", "SW.R"))

f_gauss <- gaussian()
df_gauss <- data.frame(y = rnorm(n, f_gauss$linkinv(x %*% b), dis), x = x)
f_binom <- binomial()
df_binom <- data.frame(
  y = rbinom(n, weights, f_binom$linkinv(x %*% b)),
  x = x, weights = weights
)
f_poiss <- poisson()
df_poiss <- data.frame(y = rpois(n, f_poiss$linkinv(x %*% b)), x = x)

formula <- y ~ x.1 + x.2 + x.3 + x.4 + x.5
extract_model_data <- function(object, newdata = NULL, wrhs = NULL,
                               orhs = NULL, extract_y = FALSE) {
  if (!is.null(object)) {
    formula <- formula(object)
    tt <- extract_terms_response(formula)
    response_name <- tt$response
  } else {
    response_name <- NULL
  }

  if (is.null(newdata)) {
    newdata <- object$data
  }

  resp_form <- NULL
  if (is.null(object)) {
    if ("weights" %in% colnames(newdata))
      wrhs <- ~ weights
    if ("offset" %in% colnames(newdata))
      orhs <- ~ offset
    if ("y" %in% colnames(newdata))
      resp_form <- ~ y
  }

  args <- nlist(object, newdata, wrhs, orhs, resp_form)
  return(do_call(.extract_model_data, args))
}

dref_gauss <- init_refmodel(
  object = NULL, df_gauss, formula, f_gauss,
  extract_model_data = extract_model_data
)
dref_binom <- init_refmodel(
  object = NULL, df_binom, formula, f_binom,
  extract_model_data = extract_model_data
)
dref_poiss <- init_refmodel(
  object = NULL, df_poiss, formula, f_poiss,
  extract_model_data = extract_model_data
)

dref_list <- list(gauss = dref_gauss, binom = dref_binom, poiss = dref_poiss)

SW({
  # varsel
  vsd_list <- lapply(dref_list, varsel, nterms_max = nterms + 1, verbose = FALSE)

  # cv_varsel
  cvvsd_list <- lapply(dref_list, cv_varsel,
    nterms_max = nterms + 1,
    verbose = FALSE
  )

  predd_list <- lapply(vsd_list, proj_linpred,
    newdata = data.frame(x = x, weights = weights, offset = offset),
    offsetnew = ~offset, weightsnew = ~weights, nterms = 3,
    seed = seed
  )
})

test_that("predict fails for 'datafit' objects", {
  expect_error(
    predict(dref_gauss, df_gauss),
    "Cannot make predictions with data reference only"
  )
})

test_that(paste(
  "output of varsel is sensible with only data provided as",
  "reference model"
), {
  for (i in seq_along(vsd_list)) {
    # solution_terms seems legit
    expect_equal(length(vsd_list[[i]]$solution_terms), nterms)

    # kl seems legit
    expect_equal(length(vsd_list[[i]]$kl), nterms + 1)

    # kl decreasing
    expect_equal(vsd_list[[i]]$kl, cummin(vsd_list[[i]]$kl), tolerance = 15e-2)

    # summaries seems legit
    expect_named(vsd_list[[i]]$summaries, c("sub", "ref"))
    expect_equal(length(vsd_list[[i]]$summaries$sub), nterms + 1)
    expect_named(vsd_list[[i]]$summaries$sub[[1]], c("mu", "lppd"))
    expect_named(vsd_list[[i]]$summaries$ref, c("mu", "lppd"))
  }
})

test_that(paste(
  "output of cv_varsel is sensible with only data provided as",
  "reference model"
), {
  for (i in seq_along(cvvsd_list)) {
    # solution_terms seems legit
    expect_equal(length(cvvsd_list[[i]]$solution_terms), nterms)

    # kl seems legit
    expect_equal(length(cvvsd_list[[i]]$kl), nterms + 1)

    # kl decreasing
    expect_equal(cvvsd_list[[i]]$kl, cummin(cvvsd_list[[i]]$kl),
      tolerance = 15e-2
    )

    # summaries seems legit
    expect_named(cvvsd_list[[i]]$summaries, c("sub", "ref"))
    expect_equal(length(cvvsd_list[[i]]$summaries$sub), nterms + 1)
    expect_named(cvvsd_list[[i]]$summaries$sub[[1]], c("mu", "lppd", "w"))
    expect_named(cvvsd_list[[i]]$summaries$ref, c("mu", "lppd"))
  }
})

test_that("summary.vsel stops if baseline = 'ref' and deltas = TRUE", {
  expect_error(
    summary(vsd_list[[1]], baseline = "ref", deltas = TRUE),
    paste(
      "Cannot use deltas = TRUE and baseline = 'ref' when there is no",
      "reference model"
    )
  )
})

test_that(paste("output of project is sensible with only data provided as" <
  "reference model"), {
  for (i in 1:length(vsd_list)) {

    # length of output of project is legit
    p <- project(vsd_list[[i]], nterms = 0:nterms)
    expect_equal(length(p), nterms + 1)

    for (j in 1:length(p)) {
      expect_named(p[[j]], c(
        "kl", "weights", "dis", "solution_terms", "sub_fit", "p_type",
        "family", "intercept", "extract_model_data", "refmodel"
      ), ignore.order = TRUE)
      # number of draws should equal to the number of draw weights
      ndraws <- length(p[[j]]$weights)
      expect_equal(length(p[[j]]$sub_fit$alpha), ndraws)
      expect_equal(length(p[[j]]$dis), ndraws)
      if (j > 1) {
        expect_equal(ncol(p[[j]]$sub_fit$beta), ndraws)
      }
      # j:th element should have j-1 variables
      expect_equal(length(which(p[[j]]$sub_fit$beta != 0)), j - 1)
      expect_equal(length(p[[j]]$solution_terms), j - 1)
      # family kl
      expect_equal(p[[j]]$family, vsd_list[[i]]$family)
    }
    # kl should be non-increasing on training data
    klseq <- sapply(p, function(e) e$kl)
    expect_equal(klseq, cummin(klseq), tolerance = 15e-2)

    # all submodels should use the same clustering/subsampling
    expect_equal(p[[1]]$weights, p[[nterms]]$weights)
  }
})


test_that(paste(
  "output of proj_linpred is sensible with only data provided as",
  "reference model"
), {
  for (i in 1:length(vsd_list)) {

    # length of output of project is legit
    pred <- proj_linpred(vsd_list[[i]],
      newdata = data.frame(x = x, weights = weights, offset = offset),
      seed = seed, offsetnew = ~offset, weightsnew = ~weights, nterms = 3
    )
    expect_equal(length(pred$pred), nrow(x))

    ynew <- dref_list[[i]]$y
    pred <- proj_linpred(vsd_list[[i]],
      newdata = data.frame(
        y = ynew, x = x,
        weights = weights, offset = offset
      ),
      seed = seed, offsetnew = ~offset,
      weightsnew = ~weights, nterms = 3
    )

    expect_equal(length(pred$pred), nrow(x))
    expect_equal(length(pred$lpd), nrow(x))
  }
})


# below are some tests that check Lasso solution computed with varsel is the
# same as that of glmnet. (notice that glm_ridge and glm_elnet are already
# tested separately, so these would only check that the results do not change
# due to varsel/cv_varsel etc.)

set.seed(1235)
n <- 100
nterms <- 10
x <- matrix(rnorm(n * nterms, 0, 1), n, nterms)
b <- seq(0, 1, length.out = nterms)
dis <- runif(1, 0.3, 0.5)
weights <- sample(1:4, n, replace = TRUE) #
offset <- 0.1 * rnorm(n)
seed <- 1235
source(file.path("helpers", "SW.R"))

fams <- list(gaussian(), binomial(), poisson())
x_list <- lapply(fams, function(fam) x)
y_list <- lapply(fams, function(fam) {
  if (fam$family == "gaussian") {
    y <- rnorm(n, x %*% b, 0.5)
    weights <- NULL
    y_glmnet <- y
  } else if (fam$family == "binomial") {
    y <- rbinom(n, weights, fam$linkinv(x %*% b))
    ## y <- y / weights
    ## different way of specifying binomial y for glmnet
    y_glmnet <- cbind(1 - y / weights, y / weights)
    weights <- weights
  } else if (fam$family == "poisson") {
    y <- rpois(n, fam$linkinv(x %*% b))
    y_glmnet <- y
    weights <- NULL
  }
  nlist(y, y_glmnet, weights)
})

median_lasso_preds <- list(
  c(0.2774068, 0.2857059, 0.2878935, 0.2813947, 0.2237729,
    0.2895152, 0.3225808, 0.3799348),
  c(0.009607217, 0.015400719, -0.017591445, -0.009711566,
    -0.023867036, -0.038964983, -0.036081074, -0.045065655),
  c(1.8846845, 1.8830678, 1.8731548, 1.4232035, 0.9960167,
    0.9452660, 0.6216253, 0.5856283)
)

solution_terms_lasso <- list(
  c(10, 9, 6, 8, 7, 5, 4, 3, 1, 2),
  c(10, 9, 8, 6, 7, 5, 3, 4, 2, 1),
  c(9, 10, 6, 7, 3, 5, 2, 4, 3, 1)
)

test_that(paste(
  "L1-projection with data reference gives the same results as",
  "Lasso from glmnet."
), {

  extract_model_data <- function(object, newdata = NULL, wrhs = NULL,
                                 orhs = NULL, extract_y = FALSE) {
    if (!is.null(object)) {
      formula <- formula(object)
      tt <- extract_terms_response(formula)
      response_name <- tt$response
    } else {
      response_name <- NULL
    }

    if (is.null(newdata)) {
      newdata <- object$data
    }

    resp_form <- NULL
    if (is.null(object)) {
      if ("weights" %in% colnames(newdata))
        wrhs <- ~ weights
      if ("offset" %in% colnames(newdata))
        orhs <- ~ offset
      if ("y" %in% colnames(newdata))
        resp_form <- ~ y
    }

    args <- nlist(object, newdata, wrhs, orhs, resp_form)
    return(do_call(.extract_model_data, args))
  }

  for (i in seq_along(fams)) {
    x <- x_list[[i]]
    y <- y_list[[i]]$y
    y_glmnet <- y_list[[i]]$y_glmnet
    fam <- fams[[i]]
    weights <- y_list[[i]]$weights
    if (is.null(weights)) {
      weights <- rep(1, NROW(y))
    }

    lambda_min_ratio <- 1e-7
    nlambda <- 1500

    df <- data.frame(y = y, x = x, weights = weights)
    formula <- y ~ x.1 + x.2 + x.3 + x.4 + x.5 + x.6 + x.7 + x.8 + x.9 + x.10
    # Lasso solution with projpred
    ref <- init_refmodel(
      object = NULL, data = df, formula = formula,
      family = fam, extract_model_data = extract_model_data
    )
    SW({
      vs <- varsel(ref,
        method = "l1", lambda_min_ratio = lambda_min_ratio,
        nlambda = nlambda, thresh = 1e-12
      )
    })
    pred1 <- proj_linpred(vs,
      newdata = data.frame(x = x, offset = offset, weights = weights),
      nterms = 0:nterms, transform = FALSE, offsetnew = ~offset,
    )

    # compute the results for the Lasso
    lasso <- glmnet::glmnet(x, y_glmnet,
      family = fam$family, weights = weights, offset = offset,
      lambda.min.ratio = lambda_min_ratio, nlambda = nlambda, thresh = 1e-12
    )
    solution_terms <- predict(lasso, type = "nonzero", s = lasso$lambda)
    nselected <- sapply(solution_terms, function(e) length(e))
    lambdainds <- sapply(unique(nselected), function(nterms) {
      max(which(nselected == nterms))
    })
    lambdaval <- lasso$lambda[lambdainds]
    ## pred2 <- predict(lasso,
    ##   newx = x, type = "link", s = lambdaval,
    ##   newoffset = offset
    ## )

    # check that the predictions agree (up to nterms-2 only, because glmnet
    # terminates the coefficient path computation too early for some reason)
    for (j in 1:(nterms - 2)) {
      expect_true(median(pred1[[j]]$pred) - median_lasso_preds[[i]][j] < 3e-1)
    }

    # check that the coefficients are similar
    ind <- match(vs$solution_terms, setdiff(split_formula(formula), "1"))
    if (Sys.getenv("NOT_CRAN") == "true") {
      betas <- sapply(vs$search_path$sub_fits, function(x) x$beta %||% 0)
      delta <- sapply(seq_len(nterms), function(i) {
        abs(t(betas[[i + 1]]) - lasso$beta[ind[1:i], lambdainds[i + 1]])
      })
      expect_true(median(unlist(delta)) < 6e-2)
      expect_true(median(abs(sapply(vs$search_path$sub_fits, function(x) {
        x$alpha
      }) - lasso$a0[lambdainds])) < 1.5e-1)
    } else {
      expect_true(sum(ind == solution_terms_lasso[[i]]) >= nterms / 2)
    }
  }
})
