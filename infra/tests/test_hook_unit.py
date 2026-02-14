#!/usr/bin/env python3
"""Unit tests for langfuse_hook.py

Tests the pure utility functions without requiring the langfuse package.
"""
import sys
from pathlib import Path
from unittest.mock import MagicMock

# Mock the langfuse module before importing the hook
sys.modules['langfuse'] = MagicMock()

# Add hooks directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / 'hooks'))

from langfuse_hook import extract_project_name, get_text_content, is_tool_result, get_content, merge_assistant_parts


def test_extract_project_name():
    """Test project name extraction from Claude's directory format."""
    # Standard format: -Users-username-project-name
    assert extract_project_name(Path("-Users-doneyli-djg-family-office")) == "djg-family-office"
    assert extract_project_name(Path("-Users-john-my-project")) == "my-project"

    # Nested paths with more components
    assert extract_project_name(Path("-Users-doneyli-code-my-app")) == "code-my-app"
    assert extract_project_name(Path("-Users-alice-projects-web-app")) == "projects-web-app"

    # Edge case: short path
    assert extract_project_name(Path("-Users-bob")) == "-Users-bob"

    print("✓ extract_project_name tests passed")


def test_get_content():
    """Test content extraction from various message formats."""
    # Direct content field
    assert get_content({"content": "hello"}) == "hello"

    # Nested message format
    assert get_content({"message": {"content": "nested"}}) == "nested"

    # List content
    content_list = [{"type": "text", "text": "hello"}]
    assert get_content({"content": content_list}) == content_list

    # Empty/missing content
    assert get_content({}) is None
    assert get_content({"other": "field"}) is None

    print("✓ get_content tests passed")


def test_get_text_content():
    """Test text extraction from messages."""
    # String content
    assert get_text_content({"content": "hello"}) == "hello"

    # List content with text blocks
    assert get_text_content({"content": [{"type": "text", "text": "hello"}]}) == "hello"

    # Multiple text blocks
    multi_text = {"content": [
        {"type": "text", "text": "hello"},
        {"type": "text", "text": "world"}
    ]}
    assert get_text_content(multi_text) == "hello\nworld"

    # Mixed content (text and tool_use)
    mixed = {"content": [
        {"type": "text", "text": "thinking..."},
        {"type": "tool_use", "name": "Read", "input": {}}
    ]}
    assert get_text_content(mixed) == "thinking..."

    # Nested message format
    assert get_text_content({"message": {"content": "nested"}}) == "nested"

    # Empty content
    assert get_text_content({"content": []}) == ""
    assert get_text_content({}) == ""

    print("✓ get_text_content tests passed")


def test_is_tool_result():
    """Test tool result detection."""
    # Tool result message
    tool_result_msg = {"content": [{"type": "tool_result", "tool_use_id": "123", "content": "result"}]}
    assert is_tool_result(tool_result_msg) == True

    # Regular text message
    text_msg = {"content": [{"type": "text", "text": "hello"}]}
    assert is_tool_result(text_msg) == False

    # String content (not a tool result)
    assert is_tool_result({"content": "hello"}) == False

    # Mixed content with tool result
    mixed = {"content": [
        {"type": "text", "text": "here's the result"},
        {"type": "tool_result", "tool_use_id": "456"}
    ]}
    assert is_tool_result(mixed) == True

    # Empty content
    assert is_tool_result({"content": []}) == False
    assert is_tool_result({}) == False

    print("✓ is_tool_result tests passed")


def test_merge_assistant_parts():
    """Test merging multiple assistant message parts."""
    # Empty input
    assert merge_assistant_parts([]) == {}

    # Single message (no merge needed)
    single = [{"content": [{"type": "text", "text": "hello"}]}]
    result = merge_assistant_parts(single)
    assert result["content"] == [{"type": "text", "text": "hello"}]

    # Multiple messages to merge
    parts = [
        {"content": [{"type": "text", "text": "part1"}]},
        {"content": [{"type": "text", "text": "part2"}]}
    ]
    result = merge_assistant_parts(parts)
    assert len(result["content"]) == 2
    assert result["content"][0]["text"] == "part1"
    assert result["content"][1]["text"] == "part2"

    # Nested message format
    nested_parts = [
        {"message": {"content": [{"type": "text", "text": "nested1"}]}},
        {"message": {"content": [{"type": "text", "text": "nested2"}]}}
    ]
    result = merge_assistant_parts(nested_parts)
    assert "message" in result
    assert len(result["message"]["content"]) == 2

    print("✓ merge_assistant_parts tests passed")


if __name__ == "__main__":
    test_extract_project_name()
    test_get_content()
    test_get_text_content()
    test_is_tool_result()
    test_merge_assistant_parts()
    print("\nAll unit tests passed!")
