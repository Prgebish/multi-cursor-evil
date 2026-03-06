.PHONY: test compile clean test-batch

EMACS ?= emacs
EMACSCLIENT ?= emacsclient
PACKAGE_INIT ?= (progn (setq load-prefer-newer t) (require 'package) (package-initialize))

# Run tests via emacsclient (requires running Emacs server with evil)
test:
	@$(EMACSCLIENT) -e "(progn \
		(require 'package) \
		(package-initialize) \
		(add-to-list 'load-path \"$(CURDIR)\") \
		(when (featurep 'evm-test) (unload-feature 'evm-test t)) \
		(when (featurep 'evm-themes) (unload-feature 'evm-themes t)) \
		(when (featurep 'evm) (unload-feature 'evm t)) \
		(when (featurep 'evm-core) (unload-feature 'evm-core t)) \
		(load-file \"$(CURDIR)/evm-core.el\") \
		(load-file \"$(CURDIR)/evm-themes.el\") \
		(load-file \"$(CURDIR)/evm.el\") \
		(load-file \"$(CURDIR)/test/evm-test.el\") \
		(let ((stats (ert-run-tests-batch))) \
			(message \"Tests: %d passed, %d failed\" \
				(ert-stats-completed-expected stats) \
				(ert-stats-completed-unexpected stats)) \
			(if (= (ert-stats-completed-unexpected stats) 0) \
				\"All tests passed!\" \
				(error \"Some tests failed\"))))"

# Run tests in batch mode (requires evil in load-path)
test-batch:
	$(EMACS) -Q --batch \
		--eval "$(PACKAGE_INIT)" \
		-L . \
		-l ert \
		-l test/evm-test.el \
		-f ert-run-tests-batch-and-exit

# Byte-compile
compile:
	$(EMACS) -Q --batch \
		--eval "$(PACKAGE_INIT)" \
		-L . \
		-f batch-byte-compile \
		evm-core.el evm-themes.el evm.el

# Clean compiled files
clean:
	rm -f *.elc test/*.elc

# Run tests with verbose output
test-verbose:
	$(EMACS) -Q --batch \
		--eval "$(PACKAGE_INIT)" \
		-L . \
		-l ert \
		-l test/evm-test.el \
		--eval "(ert-run-tests-batch-and-exit '(not (tag :slow)))"

# Interactive test (opens Emacs)
test-interactive:
	$(EMACS) -Q \
		-L . \
		-l test/evm-test.el \
		--eval "(ert t)"
