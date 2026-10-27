# frozen_string_literal: true

require_relative "test_helper"

# The MCP layer, tested without a deployment.
#
# This server is an adapter, so the properties that matter are the ones a harness
# depends on: every tool registers under a name a model can choose, each maps its
# arguments onto the right request, report text arrives inside the untrusted-content
# marker, and an API error becomes something the model can act on rather than a stack
# trace. HTTP is stubbed, so none of this needs a running service.
#
class McpToolsTest < McpTest
  BANNER = AgentsFyiMcp::Rendering::UNTRUSTED_BANNER
  FOOTER = AgentsFyiMcp::Rendering::UNTRUSTED_FOOTER

  # Waking a tool: the recorded transport, and the answer the tool will read.
  def answer(payload, status = 200, headers = {})
    api.respond(payload, status, headers)
    api.tools
  end

  def test_find_answer_renders_the_evidence_not_just_the_fix
    body = {
      "query" => "stream() got an unexpected keyword argument", "verdict" => "answered",
      "confidence" => "medium",
      "answer" => a_report(
        "report_id" => "77777777-7777-4777-8777-777777777777",
        "resolution" => "Pass timeout via the constructor.", "version_relation" => "exact"
      ),
      "reasons" => ["confirmed as resolved_verified by 2 other operators"],
      "caveats" => ["nobody has recorded whether this worked"],
      "dissent" => [
        {
          "report_id" => "88888888-8888-4888-8888-888888888888", "title" => "A related report",
          "reason" => "3 reported this did not help, 0 reported that it did",
          "solved_count" => 0, "not_helpful_count" => 3, "shared_signatures" => ["typeerror"]
        }
      ],
      "alternatives" => [], "signatures" => ["typeerror"], "candidates_considered" => 2,
      "relaxed" => false, "next_step" => "Apply the resolution, then record the outcome."
    }

    out = answer(body).find_answer(
      { "query" => "stream() rejected my timeout", "library" => "httpx", "client_version" => "0.28.0" }
    )

    call = api.calls[0]
    assert call.path.end_with?("/api/reports/answer")
    assert_equal "httpx", call.params["library"]
    assert_equal "0.28.0", call.params["client_version"]
    assert_includes out, "confidence: medium"
    assert_includes out, "Pass timeout via the constructor."
    assert_includes out, "why it is trustworthy"
    assert_includes out, "caveats"
    assert_includes out, "went badly"
    assert_includes out, "next: Apply the resolution"
    assert out.start_with?(BANNER)
  end

  def test_find_answer_says_there_is_no_answer_when_there_is_none
    out = answer(an_unknown_answer).find_answer({ "query" => "nothing at all" })

    assert_includes out, "verdict: unknown"
    assert_includes out, "no report in this corpus covers it"
    assert_includes out.downcase, "submit"
  end

  def test_search_maps_arguments_onto_the_query_string
    out = answer({ "items" => [a_report], "total" => 1 }).search_reports(
      { "query" => "timeout", "library" => "httpx", "signature" => "typeerror", "limit" => 3 }
    )

    call = api.calls[0]
    assert_equal "GET", call.method
    assert call.path.end_with?("/api/reports/search")
    assert_equal "timeout", call.params["q"]
    assert_equal "httpx", call.params["library"]
    assert_equal "typeerror", call.params["signature"]
    assert_equal "3", call.params["limit"]
    assert_equal "brief", call.params["view"]
    assert out.start_with?(BANNER)
    assert out.rstrip.end_with?(FOOTER)
  end

  def test_a_search_and_an_answer_count_as_demand_by_default
    # A caller's search is the only signal the service has about what people cannot
    # find, so the opt-out has to be off — and off has to mean the exact query string
    # it sent before, or every ordinary lookup silently stops being counted.
    tools = answer({ "items" => [a_report], "total" => 1 })
    tools.search_reports({ "query" => "timeout" })
    refute api.calls[0].params.key?("record")

    api.clear!
    api.respond(an_unknown_answer)
    tools.find_answer({ "query" => "timeout" })
    refute api.calls[0].params.key?("record")
  end

  def test_a_self_check_does_not_write_the_demand_table
    # The harness that measures whether a model reaches these tools drives the model
    # through this server, and the service reads its search log to decide which
    # libraries nobody can find anything about. The flag is an environment variable,
    # not a tool argument, so a model cannot decide its own lookup does not count.
    api.record = false

    tools = answer({ "items" => [a_report], "total" => 1 })
    tools.search_reports({ "query" => "timeout" })
    assert_equal "false", api.calls[0].params["record"]

    api.clear!
    api.respond(an_unknown_answer)
    tools.find_answer({ "query" => "timeout" })
    assert_equal "false", api.calls[0].params["record"]
  end

  def test_an_empty_search_says_so_and_suggests_contributing
    out = answer({ "items" => [], "total" => 0 }).search_reports({ "query" => "nothing matches this" })

    assert_includes out, "No reports matched"
    assert_includes out, "consider submitting"
  end

  def test_an_empty_search_passes_on_the_service_diagnosis
    # The service does not say the same thing about every empty page — a name it files
    # under a different spelling, a name it has never seen, and terms that simply
    # missed are three different answers — and swallowing that left a model told only
    # "no reports matched", which sends it away from a corpus that holds the report it
    # needed.
    body = {
      "items" => [], "total" => 0,
      "hint" => "No report is filed under `boolean` … This corpus does have reports for `boolean-py`."
    }

    out = answer(body).search_reports({ "query" => "no attribute 'Algebra'", "library" => "boolean" })

    assert_includes out, "boolean-py"
    assert out.index("boolean-py") < out.index("consider submitting"),
      "the correction comes before the suggestion to file a new report"
  end

  def test_the_cutoff_filter_is_sent_when_asked_for
    tools = answer({ "items" => [], "total" => 0 })
    tools.search_reports({ "query" => "timeout", "published_after" => "2025-06-01" })
    assert_equal "2025-06-01", api.calls[0].params["published_after"]

    api.clear!
    api.respond({ "items" => [], "total" => 0 })
    tools.search_reports({ "query" => "timeout" })
    refute api.calls[0].params.key?("published_after")
  end

  def test_a_dated_report_shows_when_its_release_was_published
    out = answer({ "items" => [a_report("published_at" => "2026-06-01T09:30:00Z")], "total" => 1 })
          .search_reports({ "query" => "timeout" })

    assert_includes out, "published: 2026-06-01T09:30:00Z"
  end

  def test_an_undated_report_says_nothing_about_publishing
    out = answer({ "items" => [a_report], "total" => 1 }).search_reports({ "query" => "timeout" })

    refute_includes out, "published:"
  end

  def test_search_omits_filters_it_was_not_given
    answer({ "items" => [], "total" => 0 }).search_reports({ "query" => "timeout" })

    params = api.calls[0].params
    refute params.key?("library")
    refute params.key?("version")
    refute params.key?("signature")
    refute params.key?("require_signature")
  end

  def test_require_signature_is_sent_as_a_flag
    answer({ "items" => [], "total" => 0 })
      .search_reports({ "query" => "timeout", "signature" => "typeerror", "require_signature" => true })

    assert_equal "true", api.calls[0].params["require_signature"]
  end

  def test_a_found_report_is_wrapped_and_shows_its_symptoms
    out = answer({ "items" => [a_report], "total" => 1 }).search_reports({ "query" => "stalled handshake" })

    assert_includes out, "symptoms: typeerror, stream()"
    assert_includes out, "trust: 0.7"
  end

  def test_a_clipped_report_says_how_to_get_the_rest
    out = answer({ "items" => [a_report("truncated" => true)], "total" => 1 })
          .search_reports({ "query" => "stalled handshake" })

    assert_includes out, "get_report returns it in full"
  end

  def test_precheck_posts_the_draft_and_reports_the_verdict
    body = {
      "verdict" => "likely_duplicate",
      "advice" => "A candidate carries every symptom in your draft.",
      "signatures" => ["typeerror"],
      "candidates" => [
        {
          "id" => "33333333-3333-4333-8333-333333333333", "title" => "An existing report",
          "library" => "httpx", "version" => "0.28.0", "status" => "resolved_verified",
          "trust" => 0.6, "similarity" => 0.31, "signature_overlap" => 1.0,
          "matched_signatures" => ["typeerror"]
        }
      ]
    }

    out = answer(body).precheck_report(
      {
        "title" => "The client refuses an option it does not know",
        "library" => "httpx", "version" => "0.28.0",
        "problem" => "TypeError: unexpected keyword argument"
      }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/reports/precheck")
    assert call.json["title"].start_with?("The client refuses")
    assert_includes out, "verdict: likely_duplicate"
    assert_includes out, "shared symptoms: typeerror"
    assert out.start_with?(BANNER), "candidate titles are third-party text"
  end

  def test_a_traceback_is_enough_to_precheck_with
    # The tool an agent reaches for mid-failure should accept the evidence it already
    # has, rather than demanding prose it would have to write.
    body = {
      "verdict" => "new", "advice" => "Nothing close in this library.",
      "signatures" => ["typeerror", "stream()"], "candidates" => [],
      "trace" => {
        "language" => "python", "library" => "httpx", "version" => "0.28.0",
        "exception" => "TypeError: unexpected keyword argument", "symbol" => "main",
        "location" => "/app/src/client.py:31", "frames" => ["/app/src/client.py:31"],
        "signatures" => ["typeerror"],
        "notes" => ["no library was given, so the trace's own was used: 'httpx'"]
      }
    }

    out = answer(body).precheck_report(
      { "trace" => "Traceback (most recent call last):\nTypeError: boom" }
    )

    assert_equal({ "trace" => "Traceback (most recent call last):\nTypeError: boom" }, api.calls[0].json)
    assert_includes out, "read_from_trace: TypeError: unexpected keyword argument"
    assert_includes out, "trace_identifies: httpx, 0.28.0"
    assert_includes out, "no library was given"
  end

  def test_search_can_ask_about_one_kind_of_subject
    answer({ "items" => [], "total" => 0 }).search_reports({ "query" => "timeout", "subject_kind" => "platform" })

    assert_equal "platform", api.calls[0].params["subject_kind"]
  end

  def test_a_submission_says_what_kind_of_subject_it_is
    answer(a_report("subject_kind" => "agent"), 201).submit_report(
      {
        "title" => "The harness ignores the instruction file when a subagent spawns",
        "library" => "coding-harness", "version" => "2026.3",
        "problem" => "The repository guidance is not read in a subagent.",
        "subject_kind" => "agent"
      }
    )

    assert_equal "agent", api.calls[0].json["subject_kind"]
  end

  def test_the_default_kind_is_not_carried_on_the_wire
    # A traceback-only submission is a documented shape of the call, and it stays
    # exactly that: the tool does not send a field the caller never chose.
    answer(a_report, 201).submit_report({ "library" => "httpx", "trace" => "TypeError: boom" })

    refute api.calls[0].json.key?("subject_kind")
  end

  def test_a_report_about_a_platform_is_not_labelled_a_library
    out = answer(a_report("subject_kind" => "platform")).get_report(
      { "report_id" => "11111111-1111-4111-8111-111111111111" }
    )

    assert_includes out, "subject: platform"
    assert_includes out, "platform: httpx 0.28.0"
  end

  def test_a_package_report_reads_exactly_as_it_did_before
    out = answer(a_report("subject_kind" => "package")).get_report(
      { "report_id" => "11111111-1111-4111-8111-111111111111" }
    )

    refute_includes out, "subject:"
    assert_includes out, "library: httpx 0.28.0"
  end

  def test_a_report_shows_the_evidence_its_status_was_computed_from
    report = a_report(
      "verifications" => [
        {
          "operator_id" => "22222222-2222-4222-8222-222222222222", "outcome" => "reproduced",
          "counted" => false, "environment" => nil, "notes" => nil,
          "created_at" => "2026-09-24T22:41:00Z", "updated_at" => "2026-09-24T22:41:00Z"
        },
        {
          "operator_id" => "33333333-3333-4333-8333-333333333333", "outcome" => "reproduced",
          "counted" => true, "environment" => "CPython 3.12.14; verified by executing",
          "notes" => "Asked the two releases directly: `httpx.Client(app=…)` refused it",
          "created_at" => "2026-09-24T22:42:00Z", "updated_at" => "2026-09-24T22:42:00Z"
        }
      ]
    )

    out = answer(report).get_report({ "report_id" => "11111111-1111-4111-8111-111111111111" })

    assert_includes out, "verifications: 1 counted of 2 recorded"
    assert_includes out, "not counted: recorded by the author"
    assert_includes out, "refused it"
  end

  def test_a_submission_can_be_nothing_but_a_traceback
    answer(a_report, 201).submit_report(
      { "trace" => "Traceback (most recent call last):\nTypeError: boom" }
    )

    assert_equal(
      { "trace" => "Traceback (most recent call last):\nTypeError: boom" },
      api.calls[0].json
    )
  end

  def test_the_check_takes_the_kind_the_submission_would_carry
    # A draft is checked and then filed, and the two calls have to take one body.
    answer({ "verdict" => "new", "advice" => "nothing close", "candidates" => [] })
      .precheck_report({ "title" => "A harness ignored its own annotation", "subject_kind" => "agent" })

    assert_equal "agent", api.calls[0].json["subject_kind"]
  end

  def test_precheck_does_not_carry_the_default_kind
    answer({ "verdict" => "new", "advice" => "nothing close", "candidates" => [] })
      .precheck_report({ "title" => "A failure with a package at fault" })

    refute api.calls[0].json.key?("subject_kind")
  end

  def test_a_run_states_its_kind_once
    answer(a_triage).triage_failures(
      { "failures" => [{ "title" => "The harness dropped a tool result" }], "subject_kind" => "agent" }
    )

    assert_equal "agent", api.calls[0].json["subject_kind"]
  end

  def test_a_run_of_findings_states_its_kind_once
    answer(a_batch).submit_reports(
      {
        "findings" => [{ "title" => "The harness dropped a tool result" }],
        "subject_kind" => "platform"
      }
    )

    assert_equal "platform", api.calls[0].json["subject_kind"]
  end

  def test_triage_names_the_kind_it_will_file_under
    out = answer(a_triage(kind: "agent")).triage_failures(
      { "failures" => [{ "title" => "The harness dropped a tool result" }] }
    )

    assert_includes out, "about a agent"
  end

  def test_triage_says_nothing_extra_about_a_package
    out = answer(a_triage(kind: "package")).triage_failures(
      { "failures" => [{ "title" => "A package broke on upgrade" }] }
    )

    assert_includes out, "file as: httpx 0.28.0"
    refute_includes out, "about a"
  end

  def test_find_answer_accepts_a_traceback_instead_of_a_query
    body = {
      "query" => "TypeError: unexpected keyword argument", "verdict" => "unknown",
      "confidence" => "none", "answer" => nil, "reasons" => [], "caveats" => [],
      "dissent" => [], "alternatives" => [], "next_step" => "Submit what you learn."
    }

    answer(body).find_answer({ "trace" => "Traceback (most recent call last):\nTypeError: boom" })

    call = api.calls[0]
    assert call.params["trace"].start_with?("Traceback")
    refute call.params.key?("q")
  end

  def test_triage_sends_the_whole_run_as_one_request
    body = {
      "items" => [
        {
          "index" => 0, "verdict" => "new", "action" => "submit",
          "advice" => "Nothing close in this library.",
          "title" => "TypeError: send() got an unexpected keyword argument 'retries'",
          "library" => "triageprobe", "version" => "unknown",
          "signatures" => ["typeerror"], "candidate" => nil, "candidate_count" => 0,
          "notes" => ["no library was given, so the trace's own was used: 'triageprobe'"]
        },
        {
          "index" => 1, "verdict" => "duplicate", "action" => "verify_existing",
          "advice" => "Already recorded in this library.",
          "title" => "Zephyr stalls when the handshake never completes",
          "library" => "httpx", "version" => "0.28.0", "signatures" => ["timeout"],
          "candidate" => {
            "id" => "33333333-3333-4333-8333-333333333333",
            "title" => "Zephyr stalls when the handshake never completes",
            "library" => "httpx", "version" => "0.28.0", "status" => "resolved_verified",
            "trust" => 0.6, "similarity" => 1.0, "signature_overlap" => 1.0,
            "matched_signatures" => ["timeout"]
          },
          "candidate_count" => 2, "notes" => []
        }
      ],
      "summary" => {
        "items" => 2, "new" => 1, "duplicates" => 1, "similar" => 0,
        "known_share" => 0.5, "advice" => "1 of 2 are already recorded: verify those instead."
      }
    }

    out = answer(body).triage_failures(
      {
        "failures" => [
          { "trace" => "TypeError: send() got an unexpected keyword argument 'retries'" },
          { "library" => "httpx", "title" => "Zephyr stalls when the handshake never completes" }
        ]
      }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/reports/triage")
    assert_equal 2, call.json["items"].length
    assert call.json["items"][0]["trace"].start_with?("TypeError")
    refute call.json.key?("library")

    assert_includes out, "[submit]"
    assert_includes out, "file as: triageprobe unknown"
    assert_includes out, "[verify_existing]"
    assert_includes out, "report_id 33333333-3333-4333-8333-333333333333"
    assert_includes out, "50% of this run is known"
    assert out.start_with?(BANNER)
  end

  def test_triage_can_name_the_library_for_the_whole_run
    empty = {
      "items" => [],
      "summary" => {
        "items" => 0, "new" => 0, "duplicates" => 0, "similar" => 0,
        "known_share" => 0.0, "advice" => "Nothing to triage."
      }
    }

    answer(empty).triage_failures(
      { "failures" => [{ "trace" => "ConnectionResetError: [Errno 104]" }], "library" => "myproject" }
    )

    assert_equal "myproject", api.calls[0].json["library"]
  end

  def test_triage_can_be_used_without_a_key
    empty = {
      "items" => [],
      "summary" => {
        "items" => 0, "new" => 0, "duplicates" => 0, "similar" => 0,
        "known_share" => 0.0, "advice" => "Nothing to triage."
      }
    }
    api.api_key = ""

    answer(empty).triage_failures({ "failures" => [{ "library" => "httpx", "title" => "A failure" }] })

    refute_includes api.calls[0].headers, "X-API-Key"
  end

  def test_triage_exposes_a_shape_a_model_can_fill_in
    # A bare dict argument tells a model nothing about the keys, so the entry is
    # declared and its fields are checked against what a single draft takes. The batch
    # is the same request repeated; a shape that drifted from that would be a tool a
    # model fills in with keys the service does not accept.
    triage = McpTestSupport::SURFACE["tools"].find { |tool| tool["name"] == "triage_failures" }
    precheck = McpTestSupport::SURFACE["tools"].find { |tool| tool["name"] == "precheck_report" }

    entry = def_properties(triage["inputSchema"], "failures")
    assert_equal precheck["inputSchema"]["properties"].keys.sort, entry.keys.sort
  end

  def test_a_run_can_be_filed_in_one_call_and_says_what_happened_to_each
    body = {
      "items" => [
        {
          "index" => 0, "status" => "created",
          "report_id" => "11111111-1111-4111-8111-111111111111",
          "title" => "Zephyr stalls when the handshake never completes", "detail" => nil, "notes" => []
        },
        {
          "index" => 1, "status" => "duplicate",
          "report_id" => "22222222-2222-4222-8222-222222222222",
          "title" => "Migration 0007 fails with a duplicate enum label",
          "detail" => "Possible duplicate of report 2222 — verify that one instead.",
          "notes" => ["this item named no library, so the request's was used: 'httpx'"]
        },
        {
          "index" => 2, "status" => "rejected", "title" => nil,
          "detail" => "missing title: send each missing field, or send a `trace`.", "notes" => []
        }
      ],
      "summary" => {
        "items" => 3, "created" => 1, "duplicates" => 1, "rejected" => 1, "advice" => "1 of 3 filed."
      }
    }

    out = answer(body).submit_reports({ "findings" => [{ "title" => "A finding" }], "library" => "httpx" })

    call = api.calls[0]
    assert call.path.end_with?("/api/reports/batch")
    assert_equal "POST", call.method
    assert_equal "test-key", call.headers["X-API-Key"]
    assert_equal({ "items" => [{ "title" => "A finding" }], "library" => "httpx" }, call.json)
    assert_includes out, "3 findings: 1 filed, 1 already recorded, 1 refused."
    assert_includes out, "verify that report rather than filing it again"
    assert_includes out, "missing title"
    assert_includes out, "the request's was used"
  end

  def test_the_write_batch_exposes_the_fields_a_write_takes
    # Checked against `submit_report` rather than restated: a shape that offered fewer
    # fields than a single write would be a tool a model cannot express its finding in.
    batch = McpTestSupport::SURFACE["tools"].find { |tool| tool["name"] == "submit_reports" }
    single = McpTestSupport::SURFACE["tools"].find { |tool| tool["name"] == "submit_report" }

    entry = def_properties(batch["inputSchema"], "findings")
    assert_equal single["inputSchema"]["properties"].keys.sort, entry.keys.sort
  end

  def test_precheck_can_be_used_without_a_key
    api.api_key = ""

    out = answer({ "verdict" => "new", "advice" => "Nothing close.", "candidates" => [] })
          .precheck_report({ "title" => "A draft", "library" => "httpx", "version" => "1.0.0" })

    assert_includes out, "verdict: new"
    refute_includes api.calls[0].headers, "X-API-Key"
  end

  def test_a_write_without_a_key_refuses_before_making_a_request
    api.api_key = ""

    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.record_outcome(
        { "report_id" => "44444444-4444-4444-8444-444444444444", "outcome" => "solved" }
      )
    end

    assert_includes error.message, "AGENTS_FYI_API_KEY is not set"
    assert_empty api.calls, "it should not have reached the network"
  end

  def test_a_write_sends_the_key
    body = {
      "counted" => true, "usefulness" => 1.0, "trust" => 0.7, "status" => "resolved_verified",
      "solved_count" => 1, "partial_count" => 0, "not_helpful_count" => 0
    }

    out = answer(body).record_outcome(
      { "report_id" => "44444444-4444-4444-8444-444444444444", "outcome" => "solved", "note" => "It worked." }
    )

    call = api.calls[0]
    assert_equal "test-key", call.headers["X-API-Key"]
    assert_equal({ "outcome" => "solved", "note" => "It worked." }, call.json)
    assert_includes out, "usefulness=1.0"
  end

  def test_flagging_sends_the_reason_and_reports_the_threshold
    body = {
      "report_id" => "33333333-3333-4333-8333-333333333333", "reason" => "unsafe",
      "flag_count" => 1, "hidden" => false, "hide_threshold" => 3
    }

    out = answer(body).flag_report(
      {
        "report_id" => "33333333-3333-4333-8333-333333333333", "reason" => "unsafe",
        "detail" => "It tells the reader to run a command from inside a report."
      }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/reports/33333333-3333-4333-8333-333333333333/flag")
    assert_equal(
      {
        "reason" => "unsafe",
        "detail" => "It tells the reader to run a command from inside a report."
      },
      call.json
    )
    assert_includes out, "flags=1/3"
    assert_includes out, "hidden=False"
  end

  def test_get_report_shows_the_alternatives_and_who_wrote_the_fix
    report = a_report(
      "resolution_source" => "proposed", "resolution_proposals" => 2,
      "proposed_resolutions" => [
        {
          "id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "resolution" => "Drain the pool before closing the transport.",
          "environment" => nil, "notes" => nil, "promoted" => true,
          "solved_count" => 0, "partial_count" => 0, "not_helpful_count" => 2,
          "usefulness" => 0.0, "created_at" => "2026-09-23T00:00:00Z"
        },
        {
          "id" => "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          "resolution" => "Stop accepting work, then drain with a timeout.",
          "environment" => nil, "notes" => "Costs a request in flight.", "promoted" => false,
          "solved_count" => 2, "partial_count" => 0, "not_helpful_count" => 0,
          "usefulness" => 1.0, "created_at" => "2026-09-23T00:00:01Z"
        }
      ]
    )

    out = answer(report).get_report({ "report_id" => "11111111-1111-4111-8111-111111111111" })

    assert_includes out, "resolution_source: proposed, 2 operators have proposed one"
    assert_includes out, "Drain the pool before closing the transport. [adopted]"
    assert_includes out, "Stop accepting work, then drain with a timeout."
    assert_includes out, 'resolution_id="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"'
    assert_includes out, "solved 2, partial 0, not helpful 0, usefulness 1.0"
    assert_includes out, "not helpful 2, usefulness 0.0"
    assert_includes out, 'resolution_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"'
  end

  def test_a_run_of_fixes_is_offered_with_what_each_has_earned
    body = {
      "verdict" => "answered", "confidence" => "low",
      "answer" => {
        "report_id" => "11111111-1111-4111-8111-111111111111",
        "title" => "Zephyr stalls when the handshake never completes",
        "library" => "httpx", "version" => "0.28.0", "version_relation" => "exact",
        "status" => "resolved_unverified", "trust" => 0.6,
        "problem" => "The handshake never completes.",
        "resolution" => "Raise the read timeout.", "resolution_source" => "proposed"
      },
      "fixes" => [
        {
          "resolution_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "resolution" => "Close the pool first.", "adopted" => false,
          "solved_count" => 3, "partial_count" => 0, "not_helpful_count" => 0, "usefulness" => 1.0
        },
        {
          "resolution_id" => "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          "resolution" => "Raise the read timeout.", "adopted" => true,
          "solved_count" => 0, "partial_count" => 0, "not_helpful_count" => 1, "usefulness" => 0.0
        }
      ],
      "reasons" => [],
      "caveats" => ["an alternative fix on this report has been reported solved 3 times"],
      "next_step" => "Try one, then record what happened, naming it."
    }

    out = answer(body).find_answer({ "query" => "handshake stalls" })

    assert_includes out, "fixes on offer:"
    assert_includes out, "Close the pool first. — solved 3, partial 0, not helpful 0, usefulness 1.0"
    assert_includes out, 'resolution_id="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"'
    assert_equal 1, out.scan("Raise the read timeout.").length
    assert_includes out, "(this report's own resolution, above) [adopted]"
    assert_includes out, "not helpful 1"
    assert_includes out, "an alternative fix"
  end

  def test_record_outcome_can_name_the_fix_it_was_about
    body = {
      "counted" => true, "applied_to" => "alternative",
      "resolution_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "usefulness" => 0.5, "trust" => 0.7, "status" => "resolved_unverified",
      "solved_count" => 1, "partial_count" => 1, "not_helpful_count" => 0
    }

    out = answer(body).record_outcome(
      {
        "report_id" => "11111111-1111-4111-8111-111111111111", "outcome" => "solved",
        "resolution_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      }
    )

    assert_equal(
      {
        "outcome" => "solved",
        "resolution_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
      },
      api.calls[0].json
    )
    assert_includes out, "applied_to=alternative"
  end

  def test_propose_resolution_attaches_a_fix_to_the_report_it_was_told_about
    body = {
      "report" => { "resolution_source" => "proposed", "status" => "resolved_unverified" },
      "promoted" => true, "proposals" => 1, "status" => "resolved_unverified",
      "confirmations" => 0, "confirmations_required" => 2,
      "next_step" => "Record the outcome once you have applied it."
    }

    out = answer(body).propose_resolution(
      {
        "report_id" => "44444444-4444-4444-8444-444444444444",
        "resolution" => "Close the pool before signalling shutdown.",
        "environment" => "linux, python 3.12"
      }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/reports/44444444-4444-4444-8444-444444444444/resolution")
    assert_equal(
      {
        "resolution" => "Close the pool before signalling shutdown.",
        "environment" => "linux, python 3.12"
      },
      call.json
    )
    assert_equal "test-key", call.headers["X-API-Key"]
    assert_includes out, "promoted=True"
    assert_includes out, "source=proposed"
  end

  def test_a_fix_that_did_not_replace_the_reports_own_says_so
    body = {
      "report" => { "resolution_source" => "original", "status" => "resolved_verified" },
      "detail" => "The report already carries a resolution, so yours is stored as an " \
                  "alternative rather than replacing it.",
      "promoted" => false, "proposals" => 2, "status" => "resolved_verified",
      "confirmations" => 2, "confirmations_required" => 2,
      "next_step" => "Read the report's proposal list if you want to compare the fixes."
    }

    out = answer(body).propose_resolution(
      { "report_id" => "44444444-4444-4444-8444-444444444444", "resolution" => "A different fix entirely." }
    )

    assert_includes out, "stored as an alternative"
    assert_includes out, "promoted=False"
    assert_includes out, "proposals=2"
  end

  def test_an_api_error_becomes_a_message_a_model_can_act_on
    api.respond(
      {
        "error" => {
          "type" => "conflict",
          "message" => "Possible duplicate of report abc — verify that one instead."
        }
      },
      409
    )

    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.submit_report(
        { "title" => "A title", "library" => "httpx", "version" => "0.28.0", "problem" => "A problem" }
      )
    end

    assert_includes error.message, "verify that one instead"
  end

  def test_a_plain_text_error_body_does_not_crash_the_error_path
    api.respond({ "detail" => [{ "msg" => "field required" }] }, 422)

    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.get_report({ "report_id" => "55555555-5555-4555-8555-555555555555" })
    end

    assert_includes error.message, "422"
  end

  # The ladder read: what a caller needs to name a target before it can ask for a plan. It
  # describes the digest rather than computing anything about a move, and the rendering keeps
  # the Ruby floor and the two counts of every step visible in one line each.
  # The routing read: what happens to each pin when the move's Ruby and Rails are named. The
  # rendering keeps the two things a caller acts on apart — the gems with somewhere to go,
  # and the unknowns, which are the list of what to record before trusting the answer.
  def test_plan_gem_moves_renders_the_verdicts_and_flags_the_unknowns
    body = {
      "ruby" => "2.1.10", "rails" => "4.1.0", "gems_read" => 4,
      "counts" => { "keep" => 1, "move" => 1, "replace" => 1, "remove" => 0, "blocked" => 0,
                    "unknown" => 1 },
      "stored" => false,
      "gems" => [
        { "name" => "rake", "version" => "13.0.0", "verdict" => "keep",
          "reason" => "every recorded requirement of rake 13.0.0 is satisfied" },
        { "name" => "rspec-rails", "version" => "2.13.1", "verdict" => "move", "to" => "3.0.0",
          "reason" => "requires railties ~> 3.1, and rspec-rails 3.0.0 is the newest recorded release that fits" },
        { "name" => "devise", "version" => "2.2.4", "verdict" => "replace",
          "replacement" => "devise", "requirement" => "~> 3.0", "mechanical" => true,
          "note" => "the rails4 branch is gone", "source" => "rubygems.org for devise 3.0.0" },
        { "name" => "who-knows", "version" => "1.0.0", "verdict" => "unknown",
          "reason" => "no facts are recorded for who-knows 1.0.0 — an unknown gem is not a pass" }
      ],
      "next_step" => "1 pin(s) are unknown to this corpus — not a pass."
    }

    out = answer(body).plan_gem_moves(
      { "lockfile" => "GEM\n  specs:\n    rake (13.0.0)\n", "ruby" => "2.1.10", "rails" => "4.1.0" }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/releases/route")
    assert_equal "ruby", call.json["ecosystem"]
    assert_equal "4.1.0", call.json["rails"]
    assert_includes out, "4 gem(s) pinned, routed for Ruby 2.1.10 and Rails 4.1.0"
    assert_includes out, "keep 1, move 1, replace 1, remove 0, blocked 0, unknown 1"
    refute_includes out, "KEEP  rake", "a kept gem needs no line of its own"
    assert_includes out, "MOVE  rspec-rails 2.13.1 -> 3.0.0"
    assert_includes out, "REPLACE  devise 2.2.4 -> devise ~> 3.0"
    assert_includes out, "read from: rubygems.org for devise 3.0.0"
    assert_includes out, "UNKNOWN  who-knows 1.0.0"
    assert_includes out, "1 pin(s) are unknown"
  end

  def test_rails_ladder_lists_the_steps_with_their_floors_and_counts
    body = {
      "top" => "8.1.0", "earliest" => "3.2",
      "guide" => "https://guides.rubyonrails.org/upgrading_ruby_on_rails.html",
      "components" => %w[railties actionpack],
      "counts" => { "steps" => 2, "documented" => 30, "automatic" => 7 },
      "stored" => false,
      "steps" => [
        { "name" => "Rails 4.0", "from_version" => "3.2.0", "to_version" => "4.0.0",
          "requires_ruby" => "1.9.3", "counts" => { "documented" => 22, "automatic" => 10, "manual" => 12 },
          "note" => "The largest of the steps." },
        { "name" => "Rails 4.1", "from_version" => "4.0.0", "to_version" => "4.1.0",
          "requires_ruby" => "1.9.3", "counts" => { "documented" => 8, "automatic" => 2, "manual" => 6 },
          "note" => "" }
      ],
      "next_step" => "This ladder is Rails 3.2 through 8.1.0 in 2 step(s) — read a move with /api/rails/upgrade."
    }

    out = answer(body).rails_ladder({})

    call = api.calls[0]
    assert_equal "GET", call.method
    assert call.path.end_with?("/api/rails/ladder")
    assert_empty call.params
    assert_nil call.headers["X-API-Key"]
    assert_includes out, "Rails 3.2 through 8.1.0 in 2 step(s)"
    assert_includes out, "30 documented change(s)"
    assert_includes out, "4.0.0   ← 3.2.0   Ruby 1.9.3+ — 22 documented, 12 needing a decision"
    assert_includes out, "8.1.0"
  end

  def test_rails_upgrade_plan_keeps_the_two_halves_of_a_step_apart
    out = answer(a_rails_plan_body).rails_upgrade_plan(
      { "from_version" => "3.2.22", "to_version" => "5.1.0" }
    )

    call = api.calls[0]
    assert call.path.end_with?("/api/rails/upgrade")
    assert_equal({ "from_version" => "3.2.22", "to_version" => "5.1.0" }, call.params)
    assert_nil call.headers["X-API-Key"]
    assert_includes out, "documented (Rails' own guide)"
    assert_includes out, "observed (executed here)"
    assert_includes out, "attr_accessible"
    assert_includes out, "3.2 → 4.0, Active Record"
    assert_includes out, "raises by your target"
    assert_includes out, "no call site in source"
    assert_includes out, "11111111-1111-4111-8111-111111111111"
    assert_includes out, "3 report(s) at releases in this window are not recorded as changes"
    assert_includes out, "2 report(s) about these components could not be placed"
    assert out.index("2 of which raise by the release you named.") < out.index("END UNTRUSTED")
    assert out.start_with?(BANNER)
  end

  def test_find_rails_edits_splits_the_files_and_shows_both_lines
    body = {
      "from_version" => "3.2.22", "to_version" => "6.1.0",
      "edits" => [
        {
          "path" => "app/controllers/users_controller.rb", "line" => 2,
          "text" => "  before_filter :authenticate", "after" => "  before_action :authenticate",
          "step" => "5.0.0", "subject" => "before_filter", "kind" => "renamed",
          "replacement" => "before_action", "automatic" => true, "note" => "Gone in 5.1.",
          "source" => "5.0, controller filters"
        }
      ],
      "manual" => [
        {
          "path" => "app/models/user.rb", "line" => 2, "text" => "  attr_accessible :name",
          "after" => nil, "step" => "4.0.0", "subject" => "attr_accessible", "kind" => "removed",
          "replacement" => "params.require(:user).permit(:name) in the controller",
          "automatic" => false, "note" => "Move the list to the controller.",
          "source" => "3.2 → 4.0, Mass assignment"
        }
      ],
      "counts" => { "automatic" => 1, "manual" => 1, "files" => 2, "lines" => 12 },
      "files_read" => 2, "lines_read" => 12, "truncated" => false, "stored" => false,
      "next_step" => "1 call site(s) are a whole-word rename and are ready to apply."
    }

    out = answer(body).find_rails_edits(
      {
        "from_version" => "3.2.22", "to_version" => "6.1.0",
        "files" => "### app/controllers/users_controller.rb\n  before_filter :auth\n" \
                   "### app/models/user.rb\nclass User\n  attr_accessible :name\n"
      }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/rails/scan")
    assert_equal(
      {
        "from_version" => "3.2.22", "to_version" => "6.1.0",
        "files" => [
          { "path" => "app/controllers/users_controller.rb", "text" => "  before_filter :auth" },
          { "path" => "app/models/user.rb", "text" => "class User\n  attr_accessible :name" }
        ]
      },
      call.json
    )
    assert_includes out, "  -   before_filter :authenticate"
    assert_includes out, "  +   before_action :authenticate"
    assert_includes out, "params.require(:user).permit(:name) in the controller"
    assert_includes out, "Move the list to the controller."
    assert_includes out, "line:   attr_accessible :name"
    assert_includes out, "stored: no (your files were read to answer this and kept nowhere)"
    assert out.start_with?(BANNER)
  end

  def test_find_rails_edits_refuses_a_file_argument_with_no_headers
    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.find_rails_edits(
        { "from_version" => "3.2.22", "to_version" => "6.1.0", "files" => "class User < ActiveRecord::Base\n" }
      )
    end

    assert_includes error.message, "###"
    assert_empty api.calls, "nothing is sent when the argument cannot be read"
  end

  def test_check_upgrade_names_the_change_both_releases_and_the_report
    out = answer(an_upgrade_body).check_upgrade(
      {
        "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5",
        "symbols" => "ArchiveFTModelOut"
      }
    )

    call = api.calls[0]
    assert call.path.end_with?("/api/reports/upgrade")
    assert_equal "mistralai", call.params["library"]
    assert_equal "1.9.11", call.params["from_version"]
    assert_equal "2.0.5", call.params["to_version"]
    assert_equal "ArchiveFTModelOut", call.params["symbols"]
    assert_includes out, "mistralai 1.9.11 -> 2.0.5"
    assert_includes out, "reports examined: 60"
    assert_includes out, "symbol_removed: ArchiveFTModelOut"
    assert_includes out, "broke in 2.0.5, still worked in 1.9.11"
    assert_includes out, "99999999-9999-4999-8999-999999999999"
    assert_includes out, "yours"
    assert out.start_with?(BANNER)
  end

  def test_check_upgrade_renders_a_change_that_is_not_about_the_callers_code
    body = an_upgrade_body
    body["changes"][0]["affects_your_code"] = false
    body["changes"][0]["subject"] = "AgentsCompletionStreamRequest"

    out = answer(body).check_upgrade(
      { "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5", "symbols" => "Mistral" }
    )

    assert_includes out, "not a name you asked about"
  end

  def test_a_name_the_caller_asked_about_is_never_called_one_they_did_not
    body = an_upgrade_body
    body["changes"][0] = body["changes"][0].merge(
      "title" => "mistralai 2.0.5 renamed mistralai.ArchiveFTModelOut to ArchiveOut",
      "subject" => "ArchiveFTModelOut", "change_kind" => "symbol_renamed",
      "replacement" => "ArchiveOut", "affects_your_code" => false
    )

    out = answer(body).check_upgrade(
      { "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5", "symbols" => "ArchiveOut" }
    )

    assert_includes out, "this change is where your `ArchiveOut` came from"
    refute_includes out, "not a name you asked about"

    api.clear!
    api.respond(body)
    out = api.tools.check_upgrade(
      { "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5", "symbols" => "SomethingElse" }
    )
    assert_includes out, "not a name you asked about"
  end

  def test_check_upgrade_surfaces_unclassified_reports_rather_than_hiding_them
    body = an_upgrade_body(
      "changes" => [],
      "unclassified" => [
        {
          "report_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "title" => "mistralai 2.0.5 raised on a name it used to accept",
          "version" => "2.0.5", "reason" => "no_change_recorded"
        }
      ],
      "next_step" => "Nothing is recorded as a change between 1.9.11 and 2.0.5."
    )

    out = answer(body).check_upgrade(
      { "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5" }
    )

    assert_includes out, "no_change_recorded"
    assert_includes out, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    assert_includes out, "no recorded change crosses this move."
  end

  def test_check_upgrade_says_an_unknown_name_is_unrecorded_not_safe
    body = an_upgrade_body("unknown_symbols" => ["read_gbq"])

    out = answer(body).check_upgrade(
      { "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5", "symbols" => "read_gbq" }
    )

    assert_includes out, "read_gbq"
    assert_includes out, "unrecorded, not safe"
  end

  def test_check_upgrade_needs_no_key
    api.api_key = ""

    out = answer(an_upgrade_body).check_upgrade(
      { "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5" }
    )

    assert_nil api.calls[0].headers["X-API-Key"]
    assert_includes out, "mistralai"
  end

  def test_check_upgrade_omits_symbols_when_none_were_named
    answer(an_upgrade_body("asked_symbols" => [])).check_upgrade(
      { "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5" }
    )

    refute api.calls[0].params.key?("symbols")
  end

  def test_a_report_id_can_never_escape_its_own_path_segment
    api.respond({}, 404)

    assert_raises(AgentsFyiMcp::ToolError) { api.tools.get_report({ "report_id" => "../operators/me" }) }

    url = api.calls[0].url
    assert url.end_with?("/api/reports/..%2Foperators%2Fme")
    refute_includes url, "/api/operators/me"

    assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.get_report({ "report_id" => "11111111-1111-4111-8111-111111111111?a=b" })
    end

    assert api.calls[1].path.end_with?("/api/reports/11111111-1111-4111-8111-111111111111%3Fa%3Db")
  end

  def test_every_tool_that_takes_an_id_encodes_it_the_same_way
    escaping = "../operators/me"
    encoded = AgentsFyiMcp::Encoding.quote(escaping, safe: "")

    escapes = [
      -> { api.tools.get_report({ "report_id" => escaping }) },
      -> { api.tools.claim_report({ "report_id" => escaping }) },
      -> { api.tools.release_report({ "report_id" => escaping }) },
      -> { api.tools.verify_report({ "report_id" => escaping, "outcome" => "reproduced" }) },
      -> { api.tools.record_outcome({ "report_id" => escaping, "outcome" => "solved" }) },
      -> { api.tools.flag_report({ "report_id" => escaping, "reason" => "spam" }) },
      -> { api.tools.propose_resolution({ "report_id" => escaping, "resolution" => "Do the thing." }) }
    ]

    escapes.each do |call|
      api.respond({}, 404)
      assert_raises(AgentsFyiMcp::ToolError, &call)
    end

    assert_equal 7, api.calls.length
    api.calls.each do |call|
      assert_includes call.url, "/api/reports/#{encoded}"
      refute_includes call.url, "/api/operators/me"
    end
  end

  def test_a_validation_error_carries_the_field_it_was_about
    api.respond(
      {
        "error" => {
          "type" => "validation_error", "status" => 422,
          "message" => "Request validation failed.",
          "details" => [
            {
              "field" => "reason", "message" => "Input should be 'spam', 'off_topic', 'incorrect'",
              "type" => "enum"
            },
            {
              "field" => "detail", "message" => "String should have at most 2000 characters",
              "type" => "string_too_long"
            }
          ]
        },
        "request_id" => "abc123"
      },
      422
    )

    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.flag_report({ "report_id" => "11111111-1111-4111-8111-111111111111", "reason" => "spam" })
    end

    assert_includes error.message, "Request validation failed."
    assert_includes error.message, "reason: Input should be 'spam', 'off_topic', 'incorrect'"
    assert_includes error.message, "detail: String should have at most 2000 characters"
  end

  def test_a_rate_limit_tells_the_model_how_long_to_wait
    api.respond(
      { "error" => { "type" => "rate_limited", "status" => 429, "message" => "Rate limit exceeded." } },
      429, { "retry-after" => "60" }
    )

    error = assert_raises(AgentsFyiMcp::ToolError) { api.tools.search_reports({ "query" => "timeout" }) }

    assert_includes error.message, "429"
    assert_includes error.message, "retry after 60s"
  end

  def test_a_rate_limit_without_a_header_still_says_what_to_do
    api.respond(
      { "error" => { "type" => "rate_limited", "status" => 429, "message" => "Rate limit exceeded." } },
      429
    )

    error = assert_raises(AgentsFyiMcp::ToolError) { api.tools.search_reports({ "query" => "timeout" }) }

    assert_includes error.message, "wait for the window to reset"
  end

  def test_no_error_other_than_a_rate_limit_is_given_a_retry_sentence
    api.respond(
      { "error" => { "type" => "conflict", "status" => 409, "message" => "Already recorded." } },
      409, { "retry-after" => "60" }
    )

    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.submit_report(
        { "title" => "A title", "library" => "httpx", "version" => "0.28.0", "problem" => "A problem" }
      )
    end

    refute_includes error.message, "retry after"
    refute_includes error.message, "wait for the window"
    assert_equal "409 from /api/reports: Already recorded.", error.message
  end

  def test_a_response_that_is_not_the_shape_this_tool_reads_names_the_field
    api.respond({ "verdict" => "answered" })
    error = assert_raises(AgentsFyiMcp::ToolError) { api.tools.find_answer({ "query" => "timeout" }) }
    assert_includes error.message, "`confidence`"

    body = an_upgrade_body
    body.delete("scanned")
    api.respond(body)
    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.check_upgrade({ "library" => "mistralai", "from_version" => "1.9.11", "to_version" => "2.0.5" })
    end
    assert_includes error.message, "`scanned`"

    api.respond({ "items" => [] })
    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.triage_failures({ "failures" => [{ "title" => "A failure" }] })
    end
    assert_includes error.message, "`summary`"

    api.respond({ "summary" => a_batch["summary"] })
    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.submit_reports({ "findings" => [{ "title" => "A finding" }] })
    end
    assert_includes error.message, "`items`"

    api.respond({ "status" => "open" }, 201)
    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.submit_report(
        { "title" => "A title", "library" => "httpx", "version" => "0.28.0", "problem" => "A problem" }
      )
    end
    assert_includes error.message, "`id`"
  end

  def test_a_lockfile_check_counts_the_gems_and_lists_the_no_and_unknown_ones
    body = {
      "gems_read" => 3, "ruby" => "3.3.0",
      "counts" => { "compatible" => 1, "incompatible" => 1, "unknown" => 1 },
      "gems" => [
        { "name" => "rake", "version" => "13.0.0", "compatible" => true, "reason" => "needs Ruby >= 2.0" },
        { "name" => "nokogiri", "version" => "1.15.0", "compatible" => false, "reason" => "needs Ruby < 3.3" },
        { "name" => "rexml", "version" => "3.2.5", "compatible" => nil, "reason" => "not recorded" }
      ]
    }

    out = answer(body).check_lockfile_ruby_compatibility(
      { "lockfile" => "GEM\n  rake (13.0.0)\n", "ruby" => "3.3.0" }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/releases/lockfile")
    assert_equal "ruby", call.json["ecosystem"]
    assert_includes out, "3 gem(s) pinned, checked against Ruby 3.3.0:"
    assert_includes out, "compatible 1, incompatible 1, unknown 1"
    assert_includes out, "  NO  nokogiri 1.15.0: needs Ruby < 3.3"
    assert_includes out, "  ?   rexml 3.2.5: not recorded"
    assert_includes out, "stored: no (the lockfile was read to answer and not kept)"
  end

  def test_a_ruby_compatibility_check_reads_the_declared_requirement
    body = {
      "library" => "nokogiri", "version" => "1.15.0", "ruby" => "3.3.0",
      "compatible" => false, "reason" => "declares Ruby < 3.3", "ruby_requirement" => "< 3.3.0"
    }

    out = answer(body).check_ruby_compatibility(
      { "library" => "nokogiri", "version" => "1.15.0", "ruby" => "3.3.0" }
    )

    assert_includes out, "nokogiri 1.15.0 on Ruby 3.3.0: no"
    assert_includes out, "reason: declares Ruby < 3.3"
    assert_includes out, "declared requirement: < 3.3.0"
  end

  def test_a_ruby_compatibility_check_says_unknown_not_a_pass
    body = {
      "library" => "nokogiri", "version" => "1.15.0", "ruby" => "3.3.0",
      "compatible" => nil, "reason" => "not in the corpus yet"
    }

    out = answer(body).check_ruby_compatibility(
      { "library" => "nokogiri", "version" => "1.15.0", "ruby" => "3.3.0" }
    )

    assert_includes out, "on Ruby 3.3.0: unknown"
    refute_includes out, "declared requirement:"
  end

  # The digest, rendered as the sentences a caller acts on: what happens to which gem, whether
  # a machine may make the change, and where the claim was read from — the last one because
  # this is documentation about an index rather than a compatibility matrix.
  def test_gem_migrations_says_which_of_your_gems_a_machine_may_move
    body = {
      "migrations" => [
        { "gem" => "cancan", "kind" => "replaced", "replacement" => "cancancan",
          "requirement" => "~> 1.9", "mechanical" => true, "note" => "dead since 2013",
          "source" => "rubygems.org's release history" },
        { "gem" => "therubyracer", "kind" => "removed", "replacement" => nil,
          "requirement" => nil, "mechanical" => true, "note" => "libv8 will not build",
          "source" => "rubygems.org for libv8" }
      ],
      "counts" => { "selected" => 2, "total" => 9 },
      "stored" => false,
      "next_step" => "2 of 9 migration(s) apply: 2 a machine may make (a Gemfile line), 0 need a decision."
    }

    out = answer(body).gem_migrations({ "gems" => "cancan,therubyracer" })

    call = api.calls[0]
    assert_equal "GET", call.method
    assert call.path.end_with?("/api/gems/migrations")
    assert_equal "cancan,therubyracer", call.params["gems"]
    assert_includes out, "2 of 9 migration(s) apply."
    assert_includes out, "cancan — replaced cancancan ~> 1.9 [a machine may make this change]"
    assert_includes out, "therubyracer — removed [a machine may make this change]"
    assert_includes out, "read from: rubygems.org's release history"
  end

  # No filter is the whole digest, and the call must not carry an empty `gems=`: a parameter
  # that is present and empty is a refusal on this service, not "unfiltered".
  def test_gem_migrations_with_no_filter_asks_for_the_whole_digest
    body = { "migrations" => [], "counts" => { "selected" => 0, "total" => 9 },
             "stored" => false,
             "next_step" => "This digest holds 9 migration(s) and none of them is for rails" }

    out = answer(body).gem_migrations({})

    assert_empty api.calls[0].params
    assert_includes out, "0 of 9 migration(s) apply."
    assert_includes out, "none of them is for rails"
  end

  def test_record_release_facts_parses_the_lines_and_pages_a_long_history
    # Three short batches, each under the page size, is one request; the assertion
    # that matters is the parse: `version=requirement` per line, a blank requirement
    # kept as null, and a page boundary never splitting a batch's request in two.
    body = { "recorded" => 2 }

    out = answer(body).record_release_facts(
      { "library" => "rake", "facts" => "13.0.0=>= 2.0\n13.0.1=\n\n" }
    )

    call = api.calls[0]
    assert_equal "POST", call.method
    assert call.path.end_with?("/api/releases/facts")
    assert_equal "rake", call.json["library"]
    assert_equal [
      { "version" => "13.0.0", "ruby_requirement" => ">= 2.0" },
      { "version" => "13.0.1", "ruby_requirement" => nil }
    ], call.json["facts"]
    assert_equal "Recorded 2 release(s) of rake in 1 request(s).", out
  end

  def test_record_release_facts_refuses_an_empty_list
    error = assert_raises(AgentsFyiMcp::ToolError) do
      api.tools.record_release_facts({ "library" => "rake", "facts" => "   \n" })
    end

    assert_includes error.message, "no releases were given"
    assert_empty api.calls
  end

  def test_list_upgrade_targets_names_what_each_attempt_reached
    body = {
      "count" => 3, "limit_max" => 2,
      "targets" => [
        {
          "repo_url" => "https://example.test/app", "ref" => "main", "rails_version" => "7.0.0",
          "ruby_floor" => "3.1.0", "status" => "done", "attempts" => 4,
          "last_attempt_at" => "2026-06-01T00:00:00Z", "notes" => nil, "reasons" => []
        },
        {
          "repo_url" => "https://example.test/two", "ref" => nil, "rails_version" => nil,
          "ruby_floor" => nil, "status" => "queued", "attempts" => 0,
          "last_attempt_at" => nil, "notes" => "waiting for a runner",
          "reasons" => ["no runner has claimed it"]
        }
      ],
      "next_step" => "Name a repository and this queue will fill."
    }

    out = answer(body).list_upgrade_targets({ "limit" => 25, "offset" => 0 })

    call = api.calls[0]
    assert_equal "test-key", call.headers["X-API-Key"]
    assert_includes out, "3 repository(ies) in the upgrade queue"
    assert_includes out, "one page carries at most 2; page with `offset`"
    assert_includes out, "- https://example.test/app@main"
    assert_includes out, "  Rails 7.0.0 | needs Ruby 3.1.0 | status done | 4 attempt(s) | last tried 2026-06-01T00:00:00Z"
    assert_includes out, "  note: waiting for a runner"
    assert_includes out, "  - no runner has claimed it"
    assert_includes out, "Name a repository and this queue will fill."
  end

  def test_claiming_reports_who_holds_it_and_when_it_expires
    body = {
      "action" => "claimed", "status" => "open",
      "claim" => { "held" => true, "yours" => true, "expires_at" => "2026-06-01T01:00:00Z" },
      "next_step" => "Report back when you have an outcome."
    }

    out = answer(body).claim_report({ "report_id" => "44444444-4444-4444-8444-444444444444" })

    assert_includes out, "claimed 44444444-4444-4444-8444-444444444444"
    assert_includes out, "held=True"
    assert_includes out, "yours=True"
    assert_includes out, "status=open"
  end

  def test_releasing_a_report_reports_the_state_it_returns_to
    body = {
      "action" => "released", "status" => "open",
      "claim" => { "held" => false, "yours" => false, "expires_at" => nil },
      "next_step" => "Somebody else can take it now."
    }

    out = answer(body).release_report({ "report_id" => "44444444-4444-4444-8444-444444444444" })

    assert_includes out, "released 44444444-4444-4444-8444-444444444444"
    assert_includes out, "held=False"
    assert_includes out, "status=open"
  end

  def test_verifying_a_report_says_whether_it_counted
    body = {
      "report" => { "status" => "resolved_verified" }, "confirmations" => 2,
      "confirmations_required" => 2, "counted" => false
    }

    out = answer(body).verify_report(
      { "report_id" => "44444444-4444-4444-8444-444444444444", "outcome" => "reproduced" }
    )

    assert_equal "reproduced", api.calls[0].json["outcome"]
    assert_includes out, "Recorded reproduced for 44444444-4444-4444-8444-444444444444"
    assert_includes out, "status=resolved_verified"
    assert_includes out, "confirmations=2/2"
    assert_includes out, "counted_toward_promotion=False"
  end

  private

  # The properties of an array-of-objects argument, resolved out of the schema's
  # `$defs` by the `$ref` the entry carries — the shape a model is shown for one
  # element, whatever name the schema gave the definition.
  def def_properties(schema, name)
    items = schema["properties"][name]["items"]
    key = items["$ref"].split("/").last
    schema["$defs"][key]["properties"]
  end
end
