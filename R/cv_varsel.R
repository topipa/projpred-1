#' Cross-validated variable selection (varsel)
#'
#' Perform cross-validation for the projective variable selection for a
#' generalized linear model or generalized lienar and additive multilevel
#' models.
#'
#' @name cv_varsel
#'
#' @param object Same as in \link[=varsel]{varsel}.
#' @param method Same as in \link[=varsel]{varsel}.
#' @param ndraws Number of posterior draws used for selection. Ignored if
#'   nclusters is provided or if method='L1'.
#' @param nclusters Number of clusters used for selection. Default is 1 and
#'   ignored if method='L1' (L1-search uses always one cluster).
#' @param ndraws_pred Number of samples used for prediction (after selection).
#'   Ignored if nclusters_pred is given.
#' @param nclusters_pred Number of clusters used for prediction (after
#'   selection). Default is 5.
#' @param cv_search Same as in \link[=varsel]{varsel}.
#' @param nterms_max Same as in \link[=varsel]{varsel}.
#' @param intercept Same as in \link[=varsel]{varsel}.
#' @param penalty Same as in \link[=varsel]{varsel}.
#' @param verbose Whether to print out some information during the validation,
#'   Default is TRUE.
#' @param cv_method The cross-validation method, either 'LOO' or 'kfold'.
#'   Default is 'LOO'.
#' @param nloo Number of observations used to compute the LOO validation
#'   (anything between 1 and the total number of observations). Smaller values
#'   lead to faster computation but higher uncertainty (larger errorbars) in the
#'   accuracy estimation. Default is to use all observations, but for faster
#'   experimentation, one can set this to a small value such as 100. Only
#'   applicable if \code{cv_method = 'LOO'}.
#' @param K Number of folds in the K-fold cross validation. Default is 5 for
#'   genuine reference models and 10 for datafits (that is, for penalized
#'   maximum likelihood estimation).
#' @param lambda_min_ratio Same as in \link[=varsel]{varsel}.
#' @param nlambda Same as in \link[=varsel]{varsel}.
#' @param thresh Same as in \link[=varsel]{varsel}.
#' @param regul Amount of regularization in the projection. Usually there is no
#'   need for regularization, but sometimes for some models the projection can
#'   be ill-behaved and we need to add some regularization to avoid numerical
#'   problems.
#' @param validate_search Whether to cross-validate also the selection process,
#'   that is, whether to perform selection separately for each fold. Default is
#'   TRUE and we strongly recommend not setting this to FALSE, because this is
#'   known to bias the accuracy estimates for the selected submodels. However,
#'   setting this to FALSE can sometimes be useful because comparing the results
#'   to the case where this parameter is TRUE gives idea how strongly the
#'   feature selection is (over)fitted to the data (the difference corresponds
#'   to the search degrees of freedom or the effective number of parameters
#'   introduced by the selectin process).
#' @param seed Random seed used in the subsampling LOO. By default uses a fixed
#'   seed.
#' @param search_terms User defined list of terms to consider for selection.
#' @param ... Additional arguments to be passed to the
#'   \code{get_refmodel}-function.
#'
#' @return An object of type \code{vsel} that contains information about the
#'   feature selection. The fields are not meant to be accessed directly by the
#'   user but instead via the helper functions (see the vignettes or type
#'   ?projpred to see the main functions in the package.)
#'
#' @examples
#' \donttest{
#' if (requireNamespace('rstanarm', quietly=TRUE)) {
#'   ### Usage with stanreg objects
#'   n <- 30
#'   d <- 5
#'   x <- matrix(rnorm(n*d), nrow=n)
#'   y <- x[,1] + 0.5*rnorm(n)
#'   data <- data.frame(x,y)
#'   fit <- rstanarm::stan_glm(y ~ X1 + X2 + X3 + X4 + X5, gaussian(),
#'      data=data, chains=2, iter=500)
#'   cvs <- cv_varsel(fit)
#'   plot(cvs)
#' }
#' }
#'
#' @export
cv_varsel <- function(object, ...) {
  UseMethod("cv_varsel")
}

#' @rdname cv_varsel
#' @export
cv_varsel.default <- function(object, ...) {
  refmodel <- get_refmodel(object)
  return(cv_varsel(refmodel, ...))
}

#' @rdname cv_varsel
#' @export
cv_varsel.refmodel <- function(object, method = NULL, cv_method = NULL,
                               ndraws = NULL, nclusters = NULL,
                               ndraws_pred = NULL, nclusters_pred = NULL,
                               cv_search = TRUE, nterms_max = NULL,
                               intercept = NULL, penalty = NULL, verbose = TRUE,
                               nloo = NULL, K = NULL, lambda_min_ratio = 1e-5,
                               nlambda = 150, thresh = 1e-6, regul = 1e-4,
                               validate_search = TRUE, seed = NULL,
                               search_terms = NULL, ...) {
  refmodel <- object
  ## resolve the arguments similar to varsel
  args <- parse_args_varsel(
    refmodel = refmodel, method = method, cv_search = cv_search,
    intercept = intercept, nterms_max = nterms_max, nclusters = nclusters,
    ndraws = ndraws,
    nclusters_pred = nclusters_pred,
    ndraws_pred = ndraws_pred, search_terms = search_terms
  )
  method <- args$method
  cv_search <- args$cv_search
  intercept <- args$intercept
  nterms_max <- args$nterms_max
  nclusters <- args$nclusters
  ndraws <- args$ndraws
  nclusters_pred <- args$nclusters_pred
  ndraws_pred <- args$ndraws_pred
  search_terms <- args$search_terms

  ## arguments specific to this function
  args <- parse_args_cv_varsel(
    refmodel, cv_method, K, nclusters,
    nclusters_pred
  )
  cv_method <- args$cv_method
  K <- args$K
  nclusters <- args$nclusters
  nclusters_pred <- args$nclusters_pred

  ## search options
  opt <- nlist(lambda_min_ratio, nlambda, thresh, regul)

  if (cv_method == "loo") {
    if (!(is.null(K))) warning("K provided, but cv_method is LOO.")
    sel_cv <- loo_varsel(
      refmodel = refmodel, method = method, nterms_max = nterms_max,
      ndraws = ndraws, nclusters = nclusters,
      ndraws_pred = ndraws_pred,
      nclusters_pred = nclusters_pred,
      cv_search = cv_search, intercept = intercept, penalty = penalty,
      verbose = verbose, opt = opt, nloo = nloo,
      validate_search = validate_search, seed = seed,
      search_terms = search_terms
    )
  } else if (cv_method == "kfold") {
    sel_cv <- kfold_varsel(
      refmodel = refmodel, method = method, nterms_max = nterms_max,
      ndraws = ndraws, nclusters = nclusters,
      ndraws_pred = ndraws_pred,
      nclusters_pred = nclusters_pred,
      cv_search = cv_search, intercept = intercept,
      penalty = penalty, verbose = verbose, opt = opt, K = K,
      seed = seed, search_terms = search_terms
    )
  } else {
    stop(sprintf("Unknown cross-validation method: %s.", method))
  }

  ## run the selection using the full dataset
  if (verbose) {
    print(paste("Performing the selection using all the data.."))
  }
  sel <- varsel(refmodel,
    method = method, ndraws = ndraws, nclusters = nclusters,
    ndraws_pred = ndraws_pred, nclusters_pred = nclusters_pred,
    cv_search = cv_search, nterms_max = nterms_max - 1,
    intercept = intercept, penalty = penalty, verbose = verbose,
    lambda_min_ratio = lambda_min_ratio, nlambda = nlambda, regul = regul,
    search_terms = search_terms
  )

  ## find out how many of cross-validated iterations select
  ## the same variables as the selection with all the data.
  solution_terms_cv_ch <- sapply(
    seq_len(NROW(sel_cv$solution_terms_cv)),
    function(i) {
      if (!is.character(sel_cv$solution_terms_cv[i, ])) {
        unlist(search_terms)[sel_cv$solution_terms_cv[i, ]]
      } else {
        sel_cv$solution_terms_cv[i, ]
      }
    }
  )

  ## these weights might be non-constant in case of subsampling LOO
  w <- sel_cv$summaries$sub[[1]]$w
  sel_solution_terms <- sel$solution_terms
  ## if weights are not set, then all validation folds have equal weight
  vars <- unlist(sel_solution_terms)
  pct_solution_terms_cv <- t(sapply(
    seq_along(sel_solution_terms),
    function(size) {
      c(
        size = size,
        sapply(vars, function(var) {
          sum((solution_terms_cv_ch[seq_len(size), , drop = FALSE] == var) * w,
            na.rm = TRUE
          )
        })
      )
    }
  ))

  ## create the object to be returned
  vs <- nlist(refmodel,
    search_path = sel$search_path, d_test = sel_cv$d_test,
    summaries = sel_cv$summaries, family = sel$family, kl = sel$kl,
    solution_terms = sel$solution_terms, pct_solution_terms_cv,
    nterms_max = nterms_max,
    nterms_all = count_terms_in_formula(refmodel$formula)
  )
  class(vs) <- "vsel"
  vs$suggested_size <- suggest_size(vs, warnings = FALSE)
  if (verbose) {
    print("Done.")
  }
  return(vs)
}

#
# Auxiliary function for parsing the input arguments for specific cv_varsel.
# This is similar in spirit to parse_args_varsel, that is, to avoid the main
# function to become too long and complicated to maintain.
#
# @param refmodel Reference model as extracted by get_refmodel
# @param cv_method The cross-validation method, either 'LOO' or 'kfold'.
#   Default is 'LOO'.
# @param K Number of folds in the K-fold cross validation. Default is 5 for
#   genuine reference models and 10 for datafits (that is, for penalized
#   maximum likelihood estimation).
parse_args_cv_varsel <- function(refmodel, cv_method = NULL, K = NULL,
                                 nclusters = NULL,
                                 nclusters_pred = NULL) {
  if (is.null(cv_method)) {
    if (inherits(refmodel, "datafit")) {
      ## only data given, no actual reference model
      cv_method <- "kfold"
    } else {
      cv_method <- "loo"
    }
  }

  if (!is.null(K)) {
    if (length(K) > 1 || !(is.numeric(K)) || !(K == round(K))) {
      stop("K must be a single integer value")
    }
    if (K < 2) {
      stop("K must be at least 2")
    }
    if (K > NROW(refmodel$y)) {
      stop("K cannot exceed n")
    }
  }

  if (tolower(cv_method) == "kfold" || is.null(K)) {
    if (inherits(refmodel, "datafit")) {
      K <- 10
      nclusters_pred <- 1
      nclusters <- 1
    } else {
      K <- 5
    }
  }

  cv_method <- tolower(cv_method)
  return(nlist(cv_method, K, nclusters, nclusters_pred))
}

loo_varsel <- function(refmodel, method, nterms_max, ndraws,
                       nclusters, ndraws_pred, nclusters_pred, cv_search,
                       intercept, penalty, verbose, opt, nloo = NULL,
                       validate_search = TRUE, seed = NULL,
                       search_terms = NULL) {
  ##
  ## Perform the validation of the searching process using LOO. validate_search
  ## indicates whether the selection is performed separately for each fold (for
  ## each data point)
  ##

  family <- refmodel$family
  mu <- refmodel$mu
  dis <- refmodel$dis
  ## the clustering/subsampling used for selection
  p_sel <- .get_refdist(refmodel,
    ndraws = ndraws,
    nclusters = nclusters
  )
  cl_sel <- p_sel$cl # clustering information

  ## the clustering/subsampling used for prediction
  p_pred <- .get_refdist(refmodel,
    ndraws = ndraws_pred,
    nclusters = nclusters_pred
  )
  cl_pred <- p_pred$cl

  ## fetch the log-likelihood for the reference model to obtain the LOO weights
  if (is.null(refmodel$loglik)) {
    ## case where log-likelihood not available, i.e., the reference model is not
    ## a genuine model => cannot compute LOO
    stop(
      "LOO can be performed only if the reference model is a genuine ",
      "probabilistic model for which the log-likelihood can be evaluated."
    )
  } else {
    ## log-likelihood available
    loglik <- refmodel$loglik
  }
  ## TODO: should take r_eff:s into account
  psisloo <- loo::psis(-loglik, cores = 1, r_eff = rep(1, ncol(loglik)))
  lw <- weights(psisloo)
  pareto_k <- loo::pareto_k_values(psisloo)
  n <- length(pareto_k)
  ## by default use all observations
  nloo <- min(nloo, n)

  if (nloo < 0) {
    stop("nloo must be at least 1")
  }

  ## compute loo summaries for the reference model
  loo_ref <- apply(loglik + lw, 2, log_sum_exp)
  mu_ref <- rep(0, n)
  for (i in 1:n) {
    mu_ref[i] <- mu[i, ] %*% exp(lw[, i])
  }

  ## decide which points form the validation set based on the k-values
  validset <- .loo_subsample(n, nloo, pareto_k, seed)
  inds <- validset$inds

  ## initialize matrices where to store the results
  solution_terms_mat <- matrix(nrow = n, ncol = nterms_max - 1)
  loo_sub <- matrix(nrow = n, ncol = nterms_max)
  mu_sub <- matrix(nrow = n, ncol = nterms_max)

  if (verbose) {
    print("Computing LOOs...")
    pb <- utils::txtProgressBar(min = 0, max = nloo, style = 3, initial = 0)
  }

  if (!validate_search) {
    ## perform selection only once using all the data (not separately for each
    ## fold), and perform the projection then for each submodel size
    search_path <- select(
      method = method, p_sel = p_sel, refmodel = refmodel, family = family,
      intercept = intercept, nterms_max = nterms_max, penalty = penalty,
      verbose = FALSE, opt = opt, search_terms = search_terms
    )
    solution_terms <- search_path$solution_terms
  }

  for (run_index in seq_along(inds)) {

    ## observation index
    i <- inds[run_index]

    ## reweight the clusters/samples according to the psis-loo weights
    p_sel <- .get_p_clust(
      family = family, mu = mu, dis = dis, wsample = exp(lw[, i]), cl = cl_sel
    )
    p_pred <- .get_p_clust(
      family = family, mu = mu, dis = dis, wsample = exp(lw[, i]), cl = cl_pred
    )

    if (validate_search) {
      ## perform selection with the reweighted clusters/samples
      search_path <- select(
        method = method, p_sel = p_sel, refmodel = refmodel,
        family = family, intercept = intercept, nterms_max = nterms_max,
        penalty = penalty, verbose = FALSE, opt = opt,
        search_terms = search_terms
      )
      solution_terms <- search_path$solution_terms
    }

    ## project onto the selected models and compute the prediction accuracy for
    ## the left-out point
    submodels <- .get_submodels(
      search_path = search_path, nterms = c(0, seq_along(solution_terms)),
      family = family, p_ref = p_pred, refmodel = refmodel,
      intercept = intercept, regul = opt$regul, cv_search = cv_search
    )
    summaries_sub <- .get_sub_summaries(
      submodels = submodels, test_points = c(i), refmodel = refmodel,
      family = family
    )
    for (k in seq_along(summaries_sub)) {
      loo_sub[i, k] <- summaries_sub[[k]]$lppd
      mu_sub[i, k] <- summaries_sub[[k]]$mu
    }

    ## we are always doing group selection
    ## with `match` we get the indices of the variables as they enter the
    ## solution path in solution_terms
    solution_terms_mat[i, ] <- match(solution_terms, search_terms)

    if (verbose) {
      utils::setTxtProgressBar(pb, run_index)
    }
  }

  if (verbose) {
    ## close the progress bar object
    close(pb)
  }

  ## put all the results together in the form required by cv_varsel
  summ_sub <- lapply(seq_len(nterms_max), function(k) {
    list(lppd = loo_sub[, k], mu = mu_sub[, k], w = validset$w)
  })
  summ_ref <- list(lppd = loo_ref, mu = mu_ref)
  summaries <- list(sub = summ_sub, ref = summ_ref)

  d_test <- list(
    y = refmodel$y, type = "loo",
    test_points = seq_along(refmodel$y),
    weights = refmodel$wobs,
    data = NULL
  )

  return(nlist(solution_terms_cv = solution_terms_mat, summaries, d_test))
}

kfold_varsel <- function(refmodel, method, nterms_max, ndraws,
                         nclusters, ndraws_pred,
                         nclusters_pred, cv_search, intercept, penalty,
                         verbose, opt, K, seed = NULL, search_terms = NULL) {
  ## fetch the k_fold list (or compute it now if not already computed)
  k_fold <- .get_kfold(refmodel, K, verbose, seed)

  ## check that k_fold has the correct form
  ## .validate_kfold(refmodel, k_fold, refmodel$nobs)

  K <- length(k_fold)
  family <- refmodel$family

  ## extract variables from each fit-object (samples, x, y, etc.)
  ## to a list of size K
  refmodels_cv <- lapply(k_fold, function(fold) fold$refmodel)

  # List of size K with test data for each fold
  d_test_cv <- lapply(k_fold, function(fold) {
    list(
      newdata = refmodel$fetch_data(obs = fold$omitted),
      y = refmodel$y[fold$omitted],
      weights = refmodel$wobs[fold$omitted],
      offset = refmodel$offset[fold$omitted],
      omitted = fold$omitted
    )
  })

  ## List of K elements, each containing d_train, p_pred, etc. corresponding
  ## to each fold.
  make_list_cv <- function(refmodel, d_test, msg) {
    nclusters_pred <- min(
      refmodel$nclusters_pred,
      nclusters_pred
    )
    p_sel <- .get_refdist(refmodel, ndraws, nclusters)
    p_pred <- .get_refdist(refmodel, ndraws_pred, nclusters_pred)
    newdata <- d_test$newdata
    pred <- matrix(
      as.numeric(refmodel$ref_predfun(refmodel$fit, newdata = newdata)),
      NROW(newdata), NCOL(refmodel$y)
    )
    mu_test <- family$linkinv(pred)
    nlist(refmodel, p_sel, p_pred, mu_test,
      dis = refmodel$dis, w_test = refmodel$wsample, d_test, msg
    )
  }

  msgs <- paste0(method, " search for fold ", 1:K, "/", K, ".")
  list_cv <- mapply(make_list_cv, refmodels_cv, d_test_cv, msgs,
    SIMPLIFY = FALSE
  )

  ## Perform the selection for each of the K folds
  if (verbose) {
    print("Performing selection for each fold..")
    pb <- utils::txtProgressBar(min = 0, max = K, style = 3, initial = 0)
  }
  search_path_cv <- lapply(seq_along(list_cv), function(fold_index) {
    fold <- list_cv[[fold_index]]
    family <- fold$refmodel$family
    out <- select(
      method = method, p_sel = fold$p_sel, refmodel = fold$refmodel,
      family = family, intercept = intercept, nterms_max = nterms_max,
      penalty = penalty, verbose = verbose, opt = opt,
      search_terms = search_terms
    )
    if (verbose) {
      utils::setTxtProgressBar(pb, fold_index)
    }
    out
  })

  solution_terms_cv <- t(sapply(search_path_cv, function(e) e$solution_terms))
  if (verbose) {
    close(pb)
  }

  ## Construct submodel projections for each fold
  if (verbose && cv_search) {
    print("Computing projections..")
    pb <- utils::txtProgressBar(min = 0, max = K, style = 3, initial = 0)
  }

  get_submodels_cv <- function(search_path, fold_index) {
    fold <- list_cv[[fold_index]]
    family <- fold$refmodel$family
    solution_terms <- search_path$solution_terms
    p_sub <- .get_submodels(
      search_path = search_path, nterms = c(0, seq_along(solution_terms)),
      family = family, p_ref = fold$p_pred, refmodel = fold$refmodel,
      intercept = intercept, regul = opt$regul, cv_search = FALSE
    )
    if (verbose && cv_search) {
      utils::setTxtProgressBar(pb, fold_index)
    }
    return(p_sub)
  }

  p_sub_cv <- mapply(get_submodels_cv, search_path_cv, seq_along(list_cv),
    SIMPLIFY = FALSE
  )
  if (verbose && cv_search) {
    close(pb)
  }

  ## Helper function extract and combine mu and lppd from K lists with each
  ## n/K of the elements to one list with n elements
  hf <- function(x) as.list(do.call(rbind, x))

  ## Apply some magic to manipulate the structure of the list so that instead of
  ## list with K sub_summaries each containing n/K mu:s and lppd:s, we have only
  ## one sub_summary-list that contains with all n mu:s and lppd:s.
  get_summaries_submodel_cv <- function(p_sub, fold) {
    omitted <- fold$d_test$omitted
    fold_summaries <- .get_sub_summaries(
      submodels = p_sub, test_points = omitted, refmodel = refmodel,
      family = family
    )
    lapply(fold_summaries, data.frame)
  }
  sub_cv_summaries <- mapply(get_summaries_submodel_cv, p_sub_cv, list_cv)
  sub <- apply(sub_cv_summaries, 1, hf)
  sub <- lapply(sub, function(summ) {
    summ$w <- rep(1, NROW(solution_terms_cv))
    summ$w <- summ$w / sum(summ$w)
    summ
  })

  ref <- hf(lapply(list_cv, function(fold) {
    data.frame(.weighted_summary_means(
      y_test = fold$d_test, family = family, wsample = fold$d_test$w,
      mu = fold$mu_test, dis = fold$refmodel$dis
    ))
  }))

  ## Combine also the K separate test data sets into one list
  ## with n y's and weights's.
  d_cv <- hf(lapply(d_test_cv, function(fold) {
    data.frame(
      y = fold$y, weights = fold$weights,
      test_points = fold$omitted
    )
  }))

  return(nlist(solution_terms_cv,
    summaries = list(sub = sub, ref = ref),
    d_test = c(d_cv, type = "kfold")
  ))
}


.get_kfold <- function(refmodel, K, verbose, seed) {
  ## Fetch the k_fold list or compute it now if not already computed. This
  ## function will return a list of length K, where each element is a list
  ## with fields 'refmodel' (object of type refmodel computed by init_refmodel)
  ## and index list 'test_points' that denotes which of the data points were
  ## left out for the corresponding fold.

  if (is.null(refmodel$cvfits)) {
    if (!is.null(refmodel$cvfun)) {
      # cv-function provided so perform the cross-validation now. In case
      # refmodel is datafit, cvfun will return an empty list and this will lead
      # to normal cross-validation for the submodels although we don't have an
      # actual reference model
      if (verbose && !("datafit" %in% class(refmodel))) {
        print("Performing cross-validation for the reference model..")
      }
      nobs <- NROW(refmodel$y)
      folds <- cvfolds(nobs, K = K, seed = seed)
      cvfits <- refmodel$cvfun(folds)
      cvfits <- lapply(seq_along(cvfits), function(k) {
        # add the 'omitted' indices for the cvfits
        cvfit <- cvfits[[k]]
        cvfit$omitted <- which(folds == k)
        cvfit
      })
    } else {
      ## genuine probabilistic model but no K-fold fits nor cvfun provided, so
      ## raise an error
      stop(
        "For a generic reference model, you must provide either cvfits or ",
        "cvfun for K-fold cross-validation. See function init_refmodel."
      )
    }
  } else {
    cvfits <- refmodel$cvfits
    K <- attr(cvfits, "K")
    folds <- attr(cvfits, "folds")
    cvfits <- lapply(seq_len(K), function(k) {
      cvfit <- cvfits$fits[[k]]
      obs <- seq_len(NROW(cvfits$data))
      cvfit$omitted <- obs[folds != k]
      cvfit
    })
  }

  train <- seq_along(refmodel$y)

  k_fold <- lapply(cvfits, .init_kfold_refmodel, refmodel, train)

  return(k_fold)
}

.init_kfold_refmodel <- function(cvfit, refmodel, train) {
  fold <- setdiff(
    train,
    cvfit$omitted
  )
  default_data <- refmodel$fetch_data(obs = fold)
  fetch_fold <- function(data = NULL, obs = NULL, newdata = NULL) {
    refmodel$fetch_data(obs = fold, newdata = newdata)
  }
  ref_predfun <- function(fit, newdata = default_data) {
    refmodel$ref_predfun(fit, newdata = newdata)
  }
  proj_predfun <- function(fit, newdata = default_data, weights = NULL) {
    refmodel$proj_predfun(fit, newdata = newdata, weights = weights)
  }
  if (!inherits(cvfit, "brmsfit") && !inherits(cvfit, "stanreg")) {
    fit <- NULL
  } else {
    fit <- cvfit
  }
  extract_model_data <- function(object, newdata = fetch_fold(), ...) {
    refmodel$extract_model_data(object = object, newdata = newdata)
  }
  k_refmodel <- init_refmodel(
    object = fit, data = fetch_fold(),
    formula = refmodel$formula, family = refmodel$family,
    ref_predfun = ref_predfun, div_minimizer = refmodel$div_minimizer,
    proj_predfun = proj_predfun, folds = seq_along(fold),
    extract_model_data = extract_model_data
  )
  k_refmodel$fetch_data <- fetch_fold
  k_refmodel$nclusters_pred <- min(NCOL(k_refmodel$mu), 5)
  return(nlist(refmodel = k_refmodel, omitted = cvfit$omitted))
}

.loo_subsample <- function(n, nloo, pareto_k, seed) {
  ## decide which points to go through in the validation (i.e., which points
  ## belong to the semi random subsample of validation points)

  ## set random seed but ensure the old RNG state is restored on exit
  if (exists(".Random.seed")) {
    rng_state_old <- .Random.seed
    on.exit(assign(".Random.seed", rng_state_old, envir = .GlobalEnv))
  }
  set.seed(seed)

  resample <- function(x, ...) x[sample.int(length(x), ...)]

  if (nloo < n) {
    bad <- which(pareto_k > 0.7)
    ok <- which(pareto_k <= 0.7 & pareto_k > 0.5)
    good <- which(pareto_k <= 0.5)
    inds <- resample(bad, min(length(bad), floor(nloo / 3)))
    inds <- c(inds, resample(ok, min(length(ok), floor(nloo / 3))))
    inds <- c(inds, resample(good, min(length(good), floor(nloo / 3))))
    if (length(inds) < nloo) {
      ## not enough points selected, so choose randomly among the rest
      inds <- c(inds, resample(setdiff(1:n, inds), nloo - length(inds)))
    }

    ## assign the weights corresponding to this stratification (for example, the
    ## 'bad' values are likely to be overpresented in the sample)
    w <- rep(0, n)
    w[inds[inds %in% bad]] <- length(bad) / sum(inds %in% bad)
    w[inds[inds %in% ok]] <- length(ok) / sum(inds %in% ok)
    w[inds[inds %in% good]] <- length(good) / sum(inds %in% good)
  } else {
    ## all points used
    inds <- seq_len(n)
    w <- rep(1, n)
  }

  ## ensure weights are normalized
  w <- w / sum(w)

  return(nlist(inds, w))
}
