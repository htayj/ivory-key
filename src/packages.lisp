;;;; SPDX-License-Identifier: GPL-3.0-or-later

(defpackage #:ivory-key.source
  (:use #:cl)
  (:export
   #:source-file
   #:make-source-file
   #:source-file-name
   #:source-file-text
   #:source-span
   #:make-source-span
   #:source-span-source
   #:source-span-start-byte
   #:source-span-end-byte
   #:source-span-start-line
   #:source-span-start-column
   #:source-span-end-line
   #:source-span-end-column
   #:source-span-import-stack
   #:source-span-merge
   #:source-span-location-string
   #:source-span=
   ;; Immutable semantic provenance carried by model and normalized IR.
   #:source-origin
   #:make-source-origin
   #:source-origin-definition-span
   #:source-origin-use-spans
   #:source-origin-with-use-span
   #:source-origin=))

(defpackage #:ivory-key.conditions
  (:use #:cl)
  (:import-from #:ivory-key.source
                #:source-span-location-string
                #:source-span-start-byte)
  (:export
   #:ivory-key-diagnostic
   #:make-diagnostic
   #:diagnostic-code
   #:diagnostic-severity
   #:diagnostic-message
   #:diagnostic-span
   #:diagnostic-related-spans
   #:diagnostic-hint
   #:diagnostics-in-source-order
   #:ivory-key-syntax-error
   #:syntax-error-diagnostics))

(defpackage #:ivory-key.syntax
  (:use #:cl)
  (:import-from #:ivory-key.source
                #:source-file
                #:make-source-file
                #:source-file-name
                #:source-file-text
                #:source-span
                #:make-source-span
                #:source-span-merge)
  (:import-from #:ivory-key.conditions
                #:make-diagnostic
                #:diagnostic-code
                #:diagnostic-span
                #:diagnostics-in-source-order
                #:ivory-key-syntax-error)
  (:export
   ;; Limits and lexer results.
   #:syntax-limits
   #:make-syntax-limits
   #:syntax-limits-max-bytes
   #:syntax-limits-max-token-bytes
   #:syntax-limits-max-depth
   #:*default-syntax-limits*
   #:syntax-token
   #:syntax-token-kind
   #:syntax-token-text
   #:syntax-token-value
   #:syntax-token-span
   #:syntax-comment
   #:syntax-comment-style
   #:syntax-comment-text
   #:syntax-comment-span
   #:syntax-lex-result
   #:syntax-lex-result-tokens
   #:syntax-lex-result-diagnostics
   #:syntax-lex-result-comments
   #:lex-source
   ;; Concrete syntax tree.
   #:syntax-node
   #:syntax-node-span
   #:syntax-atom
   #:syntax-atom-kind
   #:syntax-atom-text
   #:syntax-atom-value
   #:syntax-list
   #:syntax-list-children
   #:syntax-node-equal-p
   #:syntax-form->datum
   #:syntax-atom-p
   #:syntax-list-p
   #:syntax-parse-result
   #:syntax-parse-result-source
   #:syntax-parse-result-forms
   #:syntax-parse-result-diagnostics
   #:syntax-parse-result-comments
   #:syntax-parse-result-language-version
   #:syntax-parse-result-complete-p
   #:syntax-parse-result-p
   #:parse-source
   #:parse-string
   #:parse-file
   #:parse-source-or-signal
   ;; Canonical serializer.
   #:format-syntax
   #:format-parse-result
   #:format-source))

;;; These package stubs intentionally export nothing.  Their public protocols
;;; belong to the phases that implement them; having stable package names now
;;; lets the systems compose without guessing those protocols.
(defpackage #:ivory-key.model
  (:use #:cl #:ivory-key.source #:ivory-key.conditions #:ivory-key.syntax)
  (:export
   ;; Identifiers and diagnostics.
   #:identifier #:identifier-p #:make-identifier #:ensure-identifier
   #:identifier-name #:canonical-identifier-name #:identifier= #:identifier<
   #:identifier-key #:copy-identifier-list #:unique-identifiers-p
   #:canonical-identifier-set #:identifier-member-p #:lookup-identifier
   #:semantic-error #:semantic-error-message #:semantic-error-code
   #:semantic-error-object #:semantic-resolution-error
   #:semantic-validation-error #:semantic-normalization-error
   ;; Context, modifiers, topology, and placement.
   #:context-axis #:make-context-axis #:axis-name #:axis-states
   #:axis-default-state #:axis-resolution #:axis-precedence
   #:axis-valid-tuples #:axis-state-p #:find-axis
   #:context-tuple #:context-tuple-pairs #:make-context-tuple
   #:context-tuple-state #:context-tuple= #:context-tuple-key
   #:product-axes #:axes-cartesian-tuples #:allowed-product-tuples
   #:semantic-modifier-set #:make-semantic-modifier-set #:modifier-set-members
   #:modifier-set-contains-p #:modifier-set= #:modifier-set-union
   #:logical-position #:make-logical-position #:position-name #:position-label
   #:position-coordinates #:position-hand #:position-finger #:position-metadata
   #:topology #:make-topology #:topology-name #:topology-positions
   #:topology-metadata #:find-position
   #:device-placement #:make-device-placement #:placement-name
   #:placement-topology #:placement-mappings #:placement-metadata
   #:device-position-coverage #:make-device-position-coverage
   #:device-position-coverage-position #:device-position-coverage-disposition
   #:+device-position-coverage-dispositions+
   #:placement-position-coverage #:placement-coverage-for-position
   #:placement-missing-coverage-positions #:placement-coverage-complete-p
   #:validate-device-placement-coverage
   ;; Behaviors and bindings.
   #:behavior #:behavior-axis-dependencies #:behavior-children #:behavior-origin
   #:text-output #:make-text-output #:output-text
   #:named-key-output #:make-named-key-output #:named-key-name
   #:named-symbol-output #:make-named-symbol-output #:named-symbol-name
   #:command-output #:make-command-output #:command-name
   ;; Realization-owned semantic output vocabularies.
   #:+semantic-output-vocabulary-kinds+
   #:output-vocabulary-entry #:make-output-vocabulary-entry
   #:vocabulary-entry-kind #:vocabulary-entry-identity
   #:vocabulary-entry-backend #:vocabulary-entry-spelling
   #:vocabulary-entry-key #:vocabulary-entry-canonical-data
   #:output-vocabulary #:make-output-vocabulary
   #:output-vocabulary-backends #:output-vocabulary-entries
   #:output-vocabulary-canonical-data #:semantic-output-kind
   #:semantic-output-identity #:find-output-vocabulary-entry
   #:output-vocabulary-spelling #:output-vocabulary-spelling-for-output
   #:no-output-behavior #:+no-output+ #:make-no-output-behavior
   #:modifier-operation-behavior #:make-modifier-operation
   #:modifier-operation #:modifier-operation-modifier
   #:axis-operation-behavior #:make-axis-operation #:axis-operation
   #:axis-operation-axis #:axis-operation-state
   #:ordered-behavior #:make-sequence-behavior #:ordered-behaviors
   #:simultaneous-behavior #:make-simultaneous-behavior
   #:simultaneous-behaviors #:axis-choice-behavior
   #:make-axis-choice-behavior #:choice-axis #:choice-behaviors
   #:behavior-entry #:make-behavior-entry #:make-none-entry
   #:make-transparent-entry #:make-inherit-entry #:behavior-entry-tuple
   #:behavior-entry-disposition #:behavior-entry-behavior
   #:behavior-entry-inherit-tuple #:behavior-entry-origin
   #:behavior-table #:make-behavior-table
   #:behavior-table-axes #:behavior-table-entries
   #:behavior-table-allowed-tuples #:find-behavior-entry
   #:behavior-template #:make-behavior-template #:behavior-template-name
   #:behavior-template-parameters #:behavior-template-body #:behavior-template-origin
   #:behavior-template-parameter #:make-behavior-template-parameter
   #:behavior-parameter-name #:behavior-template-reference
   #:make-behavior-template-reference #:behavior-reference-name
   #:behavior-reference-arguments #:behavior-reference-origin
   #:binding #:make-binding #:binding-position #:binding-behavior
   #:binding-metadata #:binding-origin #:patch-binding #:make-patch-binding
   #:make-transparent-patch-binding #:patch-binding-position
   #:patch-binding-disposition #:patch-binding-behavior #:patch-binding-origin
   #:overlay-patch #:make-overlay-patch #:overlay-patch-name
   #:overlay-patch-axis #:overlay-patch-state #:overlay-patch-precedence
   #:overlay-patch-bindings #:overlay-patch-origin
   #:complete-behavior-p #:behavior-irreversible-p
   ;; Timed interaction model.
   #:position-selector #:make-position-selector #:position-selector-kind
   #:position-selector-positions #:any-position-selector
   #:other-than-selector #:captured-position-selector
   #:temporal-pattern #:make-temporal-pattern
   #:temporal-pattern-kind #:temporal-pattern-arguments
   #:temporal-pattern-options #:temporal-pattern-option
   #:pattern-down #:pattern-up #:pattern-sequence #:pattern-all
   #:pattern-either #:pattern-conjunction #:pattern-duration
   #:pattern-deadline #:pattern-within #:pattern-overlap #:pattern-without
   #:pattern-repeat #:pattern-capture #:pattern-context-is
   #:temporal-pattern-children #:temporal-pattern-axis-dependencies
   #:temporal-pattern-position-selectors #:temporal-pattern-finite-p
   #:interaction-effects #:make-interaction-effects #:effect-entry-behaviors
   #:effect-commit-behaviors #:effect-while-behaviors
   #:effect-exit-behaviors #:effect-cancel-behaviors #:interaction-effects-origin
   #:interaction-effects-behaviors #:interaction-candidate
   #:make-interaction-candidate #:candidate-name #:candidate-match
   #:candidate-commit #:candidate-behavior #:candidate-effects
   #:candidate-context-axes #:candidate-context-policy #:candidate-effect-start
   #:candidate-origin #:candidate-axis-dependencies #:interaction #:make-interaction
   #:interaction-name #:interaction-participants #:interaction-observe
   #:interaction-anchor #:interaction-candidates #:interaction-arbitration
   #:interaction-origin #:priority-arbitration #:longest-match-arbitration
   #:interaction-template #:make-interaction-template
   #:interaction-template-name #:interaction-template-parameters
   #:interaction-template-body #:interaction-template-reference
   #:make-interaction-template-reference #:interaction-reference-name
   #:interaction-reference-arguments #:interaction-reference-origin
   #:interaction-template-origin #:interaction-template-parameter
   #:make-interaction-template-parameter #:interaction-parameter-name
   ;; Layout, resolution, validation, and normalization.
   #:layout #:make-layout #:layout-name #:layout-topology #:layout-axes
   #:layout-modifiers #:layout-bindings #:layout-overlays
   #:layout-interactions #:layout-behavior-templates
   #:layout-interaction-templates #:layout-axis #:layout-binding
   #:layout-origin #:layout-product-axes #:binding-axis-dependencies
   #:semantic-context #:make-semantic-context #:semantic-context-values
   #:semantic-context-latches #:semantic-context-locked-axes
   #:semantic-context-state #:context-latch #:make-context-latch
   #:context-latch-axis #:context-latch-state #:context-with-latch
   #:consume-context-latches #:resolve-behavior
   #:resolve-interaction-candidate #:resolve-interaction
   #:resolve-interaction-form #:resolve-layout
   #:decode-layout-forms #:semantic-diagnostic #:make-semantic-diagnostic
   #:semantic-diagnostic-code #:semantic-diagnostic-message
   #:semantic-diagnostic-object #:validate-layout
   #:normalized-layout #:normalized-layout-name #:normalized-layout-topology
   #:normalized-layout-axes #:normalized-layout-modifiers
   #:normalized-layout-bindings #:normalized-layout-patches
   #:normalized-layout-interactions #:normalized-binding
   #:normalized-binding-position #:normalized-binding-axes
   #:normalized-binding-entries #:normalized-binding-entry
   #:make-normalized-binding-entry #:normalized-entry-tuple
   #:normalized-entry-behavior #:normalized-entry-origin
   #:normalized-binding-origin #:normalized-patch #:normalized-patch-name
   #:normalized-patch-axis #:normalized-patch-state
   #:normalized-patch-precedence #:normalized-patch-bindings #:normalized-patch-origin
   #:normalized-interaction #:normalized-interaction-name
   #:normalized-interaction-participants #:normalized-interaction-observe
   #:normalized-interaction-anchor #:normalized-interaction-candidates
   #:normalized-interaction-arbitration #:normalized-interaction-candidate
   #:normalized-interaction-origin
   #:normalized-candidate-name #:normalized-candidate-match
   #:normalized-candidate-commit #:normalized-candidate-entries
   #:normalized-candidate-effects #:normalized-candidate-context-axes
   #:normalized-candidate-context-policy #:normalized-candidate-effect-start
   #:normalized-candidate-origin #:normalized-layout-origin
   #:normalize-layout
   #:normalized-binding-entry-for-context
   #:normalized-layout-binding-for-context #:normalized-layout-key
   ;; Backend-independent realization intent.
   #:realization-profile #:make-realization-profile
   #:realization-profile-name #:realization-profile-pipeline
   #:realization-profile-placement #:realization-profile-vocabulary
   #:realization-profile-permitted-losses
   #:realization-profile-selector-policy #:realization-profile-metadata
   #:realization-selector-policy #:make-realization-selector-policy
   #:validate-realization-selector-policy
   #:realization-selector-policy-static-types
   #:realization-selector-policy-selectors
   #:realization-selector-policy-carriers
   #:realization-static-type #:make-realization-static-type
   #:realization-static-type-position #:realization-static-type-type
   #:realization-static-type-group-two-type
   #:realization-context-selector #:make-realization-context-selector
   #:realization-selector-axis #:realization-selector-state
   #:realization-selector-control #:realization-selector-consumption
   #:realization-selector-client-semantics
   #:realization-direct-carrier #:make-realization-direct-carrier
   #:realization-carrier-position #:realization-carrier-axis
   #:realization-carrier-state #:realization-carrier-linux-code
   #:realization-carrier-xkb-key
   #:realization-policy-static-type-for-position
   #:realization-policy-selector-for-axis
   #:realization-policy-carrier-for-position))

(defpackage #:ivory-key.simulate
  (:use #:cl #:ivory-key.conditions #:ivory-key.model)
  (:export
   #:timestamp
   #:timed-event #:make-timed-event #:timed-event-time #:timed-event-kind
   #:timed-event-position #:timed-event-data
   #:simulation-trace-entry #:make-simulation-trace-entry
   #:simulation-trace-entry-time #:simulation-trace-entry-kind
   #:simulation-trace-entry-event #:simulation-trace-entry-interaction
   #:simulation-trace-entry-case #:simulation-trace-entry-candidate
   #:simulation-trace-entry-details #:simulation-trace-entry-provenance
   #:event-pattern #:down-pattern #:up-pattern #:sequence-pattern #:all-pattern
   #:either-pattern #:and-pattern #:duration-pattern #:deadline-pattern
   #:within-pattern #:overlap-pattern #:without-pattern #:repeat-pattern
   #:pattern-status
   #:sim-action #:make-sim-action #:emit-action #:latch-action #:set-axis-action
   #:clear-latch-action #:sim-effect #:make-sim-effect #:sim-case #:make-sim-case
   #:sim-interaction #:make-sim-interaction
   #:simulator #:make-simulator #:simulator-feed-event #:simulator-advance-to
   #:simulator-result #:simulator-events #:simulator-trace #:simulator-outputs
   #:simulator-latches-alist #:simulator-axes-alist #:simulator-active-effect-names
   #:simulator-latch-axis #:simulator-latched-value #:simulator-set-axis
   #:simulation-result #:make-simulation-result #:simulation-result-trace
   #:simulation-result-outputs #:simulation-result-latches #:simulation-result-axes
   #:simulation-result-active-effects #:simulation-result-candidates
   #:simulate-events #:simulation-error #:malformed-event-stream
   #:simulation-ambiguity #:simulation-latch-reservation-conflict
   #:simulation-latch-reservation-conflict-axis
   #:simulation-latch-reservation-conflict-generation
   #:simulation-latch-reservation-conflict-existing-candidate
   #:simulation-latch-reservation-conflict-requested-candidate
   ;; Declarative-model adapter.
   #:model-simulation-compilation-error
   #:model-simulation-compilation-error-feature
   #:model-identifier->simulation-value #:compile-model-position-selector
   #:compile-model-temporal-pattern #:compile-model-behavior
   #:compile-model-interaction-candidate #:compile-model-interaction
   #:compile-model-interactions #:compile-normalized-interaction-candidate
   #:compile-normalized-interaction #:compile-normalized-interactions
   #:model-layout-simulator-axes #:compile-model-layout-interactions
   #:compile-normalized-ordinary-binding
   #:compile-normalized-ordinary-bindings
   #:compile-normalized-layout-simulation
   #:simulate-normalized-layout-events #:simulate-model-layout-events
   ;; Restricted declarative event-stream input and deterministic dumps.
   #:simulation-event-source-error #:simulation-event-source-error-code
   #:simulation-event-source-error-message #:simulation-event-source-error-span
   #:simulation-event-stream #:simulation-event-stream-events
   #:simulation-event-stream-axes #:simulation-event-stream-latches
   #:simulation-event-stream-until #:decode-simulation-event-stream-forms
   #:decode-simulation-event-stream-file
   #:simulate-normalized-layout-event-stream #:simulation-result-dump-string))

(defpackage #:ivory-key.project
  (:use #:cl #:ivory-key.source #:ivory-key.syntax
        #:ivory-key.conditions #:ivory-key.model)
  (:export
   #:project-error #:project-error-code #:project-error-message
   #:project-error-path #:project-error-import-stack
   #:project-definition #:project-definition-kind #:project-definition-name
   #:project-definition-value #:project-definition-span
   #:project-load-result #:project-load-result-definitions
   #:project-load-result-layouts #:project-load-result-topologies
   #:project-load-result-devices #:project-load-result-output-vocabularies
   #:project-load-result-realizations
   #:project-load-result-compositions #:project-load-result-source-paths
   #:load-project
   #:project-realization-composition
   #:project-realization-composition-name
   #:project-realization-composition-layout
   #:project-realization-composition-device
   #:project-realization-composition-realization
   #:project-definition-by-name #:project-layout #:project-topology
   #:project-device #:project-output-vocabulary
   #:project-realization #:project-composition))

(defpackage #:ivory-key.backend
  (:use #:cl #:ivory-key.conditions #:ivory-key.model)
  (:export
   #:backend #:backend-name #:backend-capabilities #:capabilities
   #:lower-request #:emit-plan #:emit-plan-to-string #:validate-artifact
   #:capability-native-level-limit #:capability-native-group-limit
   #:capability-input-identities
   #:capability-modifier-slots #:capability-interaction-features
   #:capability-output-features #:capability-validation-program
   #:capability-virtual-modifier-resources
   #:capability-context-axis-operations #:capability-resolution-styles
   #:capability-patch-operations #:capability-clock-semantics
   #:capability-lifecycle-semantics #:capability-arbitration-semantics
   #:capability-carrier-channels #:capability-platform-assumptions
   #:capability-supports-p
   #:realization-result #:make-realization-result #:realization-feature
   #:realization-grade #:realization-detail #:realization-source
   #:require-permitted-realizations
   #:key-entry-source #:make-key-entry-source #:key-entry-source-context
   #:key-entry-source-origin
   #:key-entry #:key-entry-position #:key-entry-physical-code
   #:key-entry-outputs #:key-entry-sources
   #:key-entry-code-for #:key-entry-outputs-for
   #:lowering-request #:lowering-request-name #:lowering-request-entries
   #:lowering-request-modifiers #:lowering-request-interactions
   #:lowering-request-metadata
   #:resource-pool #:make-resource-pool #:reserve-resource #:allocate-resource
   #:allocation-alist
   ;; Backend-neutral capability planning.
   #:planner-refusal #:planner-refusal-code #:planner-refusal-feature
   #:planner-refusal-detail #:planner-refusal-plan
   #:static-table-requirement #:make-static-table-requirement
   #:static-table-requirement-position
   #:static-table-requirement-physical-input
   #:static-table-requirement-axes #:static-table-requirement-entries
   #:static-table-requirement-origin
   #:static-table-requirement-state-count #:static-table-requirement-static-p
   #:static-table-bank #:make-static-table-bank
   #:static-table-bank-ordinal #:static-table-bank-capacity
   #:static-table-bank-entries
   #:static-table-bank-assignment #:make-static-table-bank-assignment
   #:static-table-bank-assignment-context
   #:static-table-bank-assignment-bank-index
   #:static-table-bank-assignment-level-index
   #:multi-bank-partition-requirement
   #:make-multi-bank-partition-requirement
   #:multi-bank-partition-requirement-position
   #:multi-bank-partition-requirement-level-capacity
   #:multi-bank-partition-requirement-bank-capacity
   #:multi-bank-partition-requirement-bank-count
   #:multi-bank-partition-requirement-banks
   #:multi-bank-partition-requirement-assignments
   #:bank-selector-requirement #:make-bank-selector-requirement
   #:bank-selector-requirement-position
   #:bank-selector-requirement-bank-count
   #:bank-selector-requirement-carrier-value-count
   #:planned-binding #:make-planned-binding
   #:selector-requirement #:make-selector-requirement
   #:selector-requirement-axis #:selector-requirement-resolution
   #:selector-requirement-states #:selector-requirement-default-state
   #:selector-requirement-positions
   #:modifier-requirement #:make-modifier-requirement
   #:modifier-requirement-modifier
   #:planner-resource-requirement #:make-planner-resource-requirement
   #:planner-resource-requirement-kind #:planner-resource-requirement-owner
   #:planner-resource-requirement-cardinality
   #:planner-resource-requirement-detail #:planner-resource-requirement-source
   #:planner-resource-requirement-origins
   #:planner-allocation #:make-planner-allocation
   #:planner-allocation-requirement #:planner-allocation-pool-kind
   #:planner-allocation-value #:planner-allocation-origins
   #:lowering-plan #:make-lowering-plan #:lowering-plan-layout
   #:lowering-plan-placement #:lowering-plan-bindings
   #:lowering-plan-selector-requirements
   #:lowering-plan-modifier-requirements
   #:lowering-plan-resource-requirements #:lowering-plan-allocations
   #:lowering-plan-multi-bank-partition-requirements
   #:lowering-plan-bank-selector-requirements
   #:lowering-plan-realizations #:lowering-plan-diagnostics
   #:plan-normalized-layout #:require-planned-realizations
   #:make-xkb-backend #:xkb-plan-realizations
   #:make-kanata-backend #:kanata-plan-realizations
   #:make-qmk-backend #:qmk-plan-keyboard #:qmk-plan-layout
   #:qmk-plan-layers #:qmk-plan-realizations
   #:pipeline-artifact-kind #:pipeline-artifact-relative-path
   #:pipeline-artifact-content #:pipeline-result-request
   #:pipeline-result-artifacts #:pipeline-result-realizations
   #:pipeline-result-allocations #:compile-xkb-kanata-request
   #:write-pipeline-result #:validate-pipeline-result))

(defpackage #:ivory-key.report
  (:use #:cl)
  (:export #:write-realization-report #:realization-report-string))

(defpackage #:ivory-key.build-contract
  (:use #:cl)
  (:export
   #:sha256-hex
   #:source-hash-record #:make-source-hash-record
   #:source-hash-record-path #:source-hash-record-sha256
   #:build-contract #:make-build-contract
   #:write-build-contract-files #:build-contract-report-string
   #:preflight-build-contract-directory))

(defpackage #:ivory-key.cli
  (:use #:cl #:ivory-key.conditions #:ivory-key.source #:ivory-key.syntax)
  (:export
   #:main
   #:compiler-stage-error #:compiler-stage-error-stage
   #:compiler-stage-error-code #:compiler-stage-error-message
   #:load-layout-for-compilation
   #:load-project-composition-for-compilation
   #:make-lowering-request-from-normalized-layout
   #:compile-layout-source #:dump-normalized-layout
   #:compile-project-source #:explain-project-source
   #:level-report-string #:simulate-layout-events
   #:preflight-build-directory #:validate-build-directory))

(defpackage #:ivory-key.migration
  (:use #:cl #:ivory-key.source)
  (:export #:inventory-manna-cadet #:write-inventory-report
           #:manna-cadet-inventory))
