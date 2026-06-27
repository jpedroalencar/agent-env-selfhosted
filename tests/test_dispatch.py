"""Tests for migrated Context Planner components.

Verifies parser, classifier, and intent mapper behave correctly
in the Platform. Inherits Hermes' original behavior.
"""

from __future__ import annotations

import pytest

from pilot.dispatch._classifier import classify
from pilot.dispatch._parser import parse as _parse
from pilot.dispatch._types import RequestShape
from pilot.dispatch.intent_mapper import shape_to_intent


# ── Parser tests (behavior preserved from Hermes) ────────────────────────────


class TestParser:
    """Parser behavior matches Hermes original."""

    def test_question_detection(self):
        p = _parse("What is the capital of France?")
        assert p.has_question is True

    def test_no_question(self):
        p = _parse("Fix the authentication bug")
        assert p.has_question is False

    def test_question_word(self):
        p = _parse("How does this work")
        assert p.has_question is True

    def test_imperative_verb(self):
        p = _parse("Fix the bug in auth module")
        assert "fix" in p.imperative_verbs

    def test_no_imperative_verb(self):
        p = _parse("What is the bug")
        assert p.imperative_verbs == []

    def test_url_extraction(self):
        p = _parse("Check https://example.com/page for details")
        assert "https://example.com/page" in p.urls

    def test_empty_input(self):
        p = _parse("")
        assert p.has_question is False
        assert p.imperative_verbs == []
        assert p.char_length == 0

    def test_very_long_input_truncated(self):
        long_text = "x" * 20_000
        p = _parse(long_text)
        assert p.truncated_input is True
        assert p.char_length == 10_000

    def test_skill_mentions(self):
        p = _parse("Use stock-bull-bear-report to analyze", ["stock-bull-bear-report"])
        assert "stock-bull-bear-report" in p.explicit_skill_mentions

    def test_command_prefix(self):
        p = _parse("/deploy to production")
        assert p.command_prefix == "deploy"


# ── Classifier tests (behavior preserved from Hermes) ────────────────────────


class TestClassifier:
    """Classifier behavior matches Hermes original."""

    def test_code_change(self):
        p = _parse("Fix the bug in authentication module")
        assert classify(p) == RequestShape.CODE_CHANGE

    def test_code_question(self):
        p = _parse("How does the auth module handle tokens?")
        assert classify(p) == RequestShape.CODE_QUESTION

    def test_research(self):
        p = _parse("What is the capital of France?")
        assert classify(p) == RequestShape.RESEARCH

    def test_casual(self):
        p = _parse("Hello there")
        assert classify(p) == RequestShape.CASUAL_CONVERSATION

    def test_ambiguous(self):
        p = _parse("")
        assert classify(p) == RequestShape.AMBIGUOUS

    def test_hermes_self_service(self):
        p = _parse("Configure hermes to use a different model")
        assert classify(p) == RequestShape.HERMES_SELF_SERVICE


# ── Intent mapper tests ──────────────────────────────────────────────────────


class TestIntentMapper:
    """RequestShape → Platform intent mapping."""

    def test_code_change_maps_to_code_change(self):
        assert shape_to_intent(RequestShape.CODE_CHANGE) == "code_change"

    def test_code_question_maps_to_code_question(self):
        assert shape_to_intent(RequestShape.CODE_QUESTION) == "code_question"

    def test_research_maps_to_research(self):
        assert shape_to_intent(RequestShape.RESEARCH) == "research"

    def test_casual_maps_to_casual(self):
        assert shape_to_intent(RequestShape.CASUAL_CONVERSATION) == "casual"

    def test_ambiguous_maps_to_ambiguous(self):
        assert shape_to_intent(RequestShape.AMBIGUOUS) == "ambiguous"

    def test_multi_step_maps_to_multi_step(self):
        assert shape_to_intent(RequestShape.MULTI_STEP_WORKFLOW) == "multi_step"

    def test_unknown_shape_falls_back(self):
        # Create a fake shape that isn't in the mapping
        class FakeShape:
            name = "FAKE"
        assert shape_to_intent(FakeShape()) == "ambiguous"

    def test_every_shape_has_mapping(self):
        """Every RequestShape value must have an explicit mapping."""
        for shape in RequestShape:
            intent = shape_to_intent(shape)
            assert isinstance(intent, str), f"{shape} maps to non-string"
            assert intent, f"{shape} maps to empty string"


# ── End-to-end dispatch tests ────────────────────────────────────────────────


class TestDispatchPipeline:
    """Parser → Classifier → Mapper produces valid Platform intents."""

    def test_financial_question_goes_to_research(self):
        p = _parse("Which profile should handle a financial analysis?")
        shape = classify(p)
        intent = shape_to_intent(shape)
        assert intent == "research"

    def test_code_fix_goes_to_code_change(self):
        p = _parse("Fix the authentication bug in login.py")
        shape = classify(p)
        intent = shape_to_intent(shape)
        assert intent == "code_change"

    def test_greeting_goes_to_casual(self):
        p = _parse("Hello")
        shape = classify(p)
        intent = shape_to_intent(shape)
        assert intent == "casual"

    def test_deterministic(self):
        """Same input always produces same output."""
        messages = [
            "Fix the bug",
            "What is the price?",
            "Hello",
            "Deploy to production",
        ]
        for msg in messages:
            first = shape_to_intent(classify(_parse(msg)))
            for _ in range(5):
                assert shape_to_intent(classify(_parse(msg))) == first
