"""Pure local-notes contract tests; no MLX installation or network required."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import contextlib
import io
import os
import subprocess
import sys
import time

HELPER = Path(__file__).resolve().parents[2] / "apps/macos/Sources/RecnyCore/Resources/recny_local_notes.py"
spec = importlib.util.spec_from_file_location("local_notes", HELPER)
notes = importlib.util.module_from_spec(spec) if HELPER.exists() else None
if notes:
    spec.loader.exec_module(notes)


class CharacterTokenizer:
    def encode(self, text, **kwargs):
        return list(text)

    def decode(self, tokens):
        return "".join(tokens)

    def apply_chat_template(self, messages, **kwargs):
        return "<chat>" + "".join(m["content"] for m in messages) + "<assistant>"


def sections(ids=("s1",), text="Обсудили тестирование."):
    return [{"title": "Обсуждение", "items": [{"text": text, "sourceIDs": list(ids)}]}]


class LocalNotesTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(notes, "The local notes helper must exist")

    def test_packing_counts_template_and_output_reserve_and_keeps_all_text(self):
        source = [{"id": "s1", "text": "Привет мир. " * 1400, "start": 0, "end": 1},
                  {"id": "s2", "text": "Завершение.", "start": 1, "end": 2}]
        tokenizer = CharacterTokenizer()
        chunks = notes.pack_segments(source, tokenizer, "meeting", context_tokens=6000, output_tokens=800)
        self.assertGreater(len(chunks), 1)
        for chunk in chunks:
            prompt = notes.build_prompt(tokenizer, chunk, "meeting")
            self.assertLessEqual(len(tokenizer.encode(prompt)) + 800, 6000)
        for item in source:
            self.assertEqual("".join(s["text"] for c in chunks for s in c if s["id"] == item["id"]), item["text"])

    def test_tokenizer_never_receives_unbounded_remaining_text(self):
        class BoundedTokenizer(CharacterTokenizer):
            def encode(self, text, **kwargs):
                if len(text) > 8192 * 8:
                    raise AssertionError("Unbounded tokenizer input")
                return super().encode(text, **kwargs)
        source = [{"id": "s1", "text": "a" * 100000, "start": None, "end": None}]
        chunks = notes.pack_segments(source, BoundedTokenizer(), "meeting")
        self.assertEqual("".join(s["text"] for c in chunks for s in c), source[0]["text"])

    def test_native_library_diagnostics_are_suppressed(self):
        program = """import importlib.util, os
spec=importlib.util.spec_from_file_location('worker', HELPER_PATH)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def fail(*args):
    os.write(1,b'PRIVATE STDOUT\\n'); os.write(2,b'PRIVATE STDERR\\n')
    raise ValueError('PRIVATE')
m.analyze_file=fail
raise SystemExit(m.main(['analyze','--model-dir','m','--input','i','--output','o']))
""".replace("HELPER_PATH", repr(str(HELPER)))
        run = subprocess.run([sys.executable, "-c", program], capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertNotIn("PRIVATE", run.stdout + run.stderr)
        self.assertEqual(json.loads(run.stdout)["message"], "local_notes_failed")

    def test_parse_valid_json_and_single_fence(self):
        payload = json.dumps({"sections": sections()})
        for text in (payload, "```json\n" + payload + "\n```"):
            self.assertEqual(notes.parse_sections(text, {"s1"}), sections())

    def test_reject_malformed_or_extra_prose(self):
        for text in ('{"sections":', 'Result: {"sections": []}', '```json\n{}', '{"sections":[],"sections":[]}',
                     '{"sections":[{"title":"Тема","items":[{"text":"Факт","sourceIDs":["s1"]}]}}'):
            with self.subTest(text=text), self.assertRaises(notes.NotesError):
                notes.parse_sections(text, {"s1"})

    def test_generation_schema_requires_exact_keys_and_known_source_ids(self):
        schema = notes.generation_schema({"s2", "s1"})
        self.assertEqual(schema["required"], ["sections"])
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(schema["properties"]["sections"]["required"], list(notes.PRESET_HEADINGS["meeting"]))
        self.assertEqual(notes.generation_schema({"s1"}, "interview")["properties"]["sections"]["maxItems"], 8)
        item = schema["properties"]["sections"]["properties"]["Обсуждение"]["items"]
        self.assertEqual(set(item["required"]), {"text", "sourceIDs"})
        self.assertFalse(item["additionalProperties"])
        self.assertEqual(item["properties"]["sourceIDs"]["items"]["enum"], ["s1", "s2"])

    def test_prompt_preserves_negative_constraints_and_certainty(self):
        prompt = notes.build_prompt(CharacterTokenizer(), [{"id": "s1", "text": "Текст", "start": None, "end": None}], "meeting")
        self.assertIn("Preserve explicit negation", prompt)
        self.assertIn("certainty", prompt)
        self.assertIn("Do not repeat", prompt)

    def test_fixed_sections_normalize_empty_sections_without_inventing_facts(self):
        value = {title: [] for title in notes.PRESET_HEADINGS["meeting"]}
        value["Обсуждение"] = sections()[0]["items"]
        self.assertEqual(notes.parse_sections(json.dumps({"sections": value}), {"s1"}, "meeting"), sections())
        del value["Действия"]
        with self.assertRaises(notes.NotesError):
            notes.parse_sections(json.dumps({"sections": value}), {"s1"}, "meeting")

    def test_generation_retries_once_with_reserved_prompt_on_missing_coverage(self):
        value = {"preset": "meeting", "segments": [{"id": identifier, "text": "Текст", "start": None, "end": None} for identifier in ("s1", "s2")]}
        calls = []
        def generate(prompt):
            calls.append(prompt)
            return json.dumps({"sections": sections(("s1",) if len(calls) == 1 else ("s1", "s2"))}), "stop"
        result = notes.analyze_payload(value, CharacterTokenizer(), generate, "a" * 40)
        self.assertEqual(len(calls), 2)
        self.assertIn("previous response failed validation", calls[1])
        self.assertEqual(result["sections"][0]["items"][0]["sourceIDs"], ["s1", "s2"])
        calls.clear()
        with self.assertRaises(notes.NotesError):
            notes.analyze_payload(value, CharacterTokenizer(), lambda prompt: (calls.append(prompt) or '{}', "stop"), "a" * 40)
        self.assertEqual(len(calls), 2)

    def test_packing_limits_source_count_and_reserves_retry_prompt(self):
        source = [{"id": f"s{i}", "text": "Текст", "start": None, "end": None} for i in range(50)]
        tokenizer = CharacterTokenizer()
        chunks = notes.pack_segments(source, tokenizer, "meeting", 6000, 800)
        self.assertTrue(all(len(chunk) <= 8 for chunk in chunks))
        for chunk in chunks:
            self.assertLessEqual(len(tokenizer.encode(notes.build_prompt(tokenizer, chunk, "meeting", retry=True))) + 800, 6000)

    @unittest.skipUnless(importlib.util.find_spec("lmformatenforcer"), "Optional grammar runtime is not installed")
    def test_grammar_rejects_wrong_bracket_extra_key_and_early_eos(self):
        from lmformatenforcer import TokenEnforcerTokenizerData
        valid = json.dumps({"sections": sections()}, ensure_ascii=False, separators=(",", ":"))
        alphabet = sorted(set(valid + 'extra_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz}[]'))
        ids = {character: index for index, character in enumerate(alphabet)}
        eos = len(alphabet)
        data = TokenEnforcerTokenizerData([(index, character, False) for character, index in ids.items()],
                                         lambda sequence: "".join(alphabet[index] for index in sequence), eos, False, eos + 1)
        enforcer = notes.make_schema_enforcer(data, {"s1"}, "interview")
        prefix = []
        for character in valid:
            allowed = enforcer.get_allowed_tokens(prefix).allowed_tokens
            self.assertNotIn(eos, allowed, f"Stopped before character {len(prefix)}")
            self.assertIn(ids[character], allowed)
            prefix.append(ids[character])
        allowed = enforcer.get_allowed_tokens(prefix).allowed_tokens
        self.assertIn(eos, allowed)
        self.assertNotIn(ids["}"], allowed)
        self.assertNotIn(ids["["], allowed)

    def test_reject_invalid_references_missing_coverage_and_empty_content(self):
        for value in (sections(("s2",)), sections(()), [], sections(("s1",), "")):
            with self.subTest(value=value), self.assertRaises(notes.NotesError):
                notes.parse_sections(json.dumps({"sections": value}), {"s1"})
        with self.assertRaises(notes.NotesError):
            notes.parse_sections(json.dumps({"sections": sections()}), {"s1", "s2"})

    def test_generation_requires_explicit_stop(self):
        for reason in (None, "length", "error"):
            with self.subTest(reason=reason), self.assertRaises(notes.NotesError):
                notes.finish_generation('{"sections":[]}', reason)
        self.assertEqual(notes.finish_generation("{}", "stop"), "{}")

    def test_batch_reduction_preserves_coverage_and_deduplicates(self):
        result = notes.reduce_sections([sections(), sections(("s2",)), sections()], {"s1", "s2"})
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["items"][0]["sourceIDs"], ["s1", "s2"])
        with self.assertRaises(notes.NotesError):
            notes.reduce_sections([sections()], {"s1", "s2"})

    def test_incomplete_model_is_not_ready_without_importing_mlx(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory)
            self.assertFalse(notes.model_status(model)["ready"])
            (model / "config.json").write_text("{}")
            (model / "manifest.json").write_text(json.dumps({"model": notes.MODEL_ID, "revision": "a" * 40, "files": {"config.json": 2}}))
            self.assertFalse(notes.model_status(model)["ready"])
            with self.assertRaises(notes.NotesError):
                notes.require_model(model)

    def test_complete_manifest_and_truncated_shard(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory)
            files = {"config.json": '{"model_type":"qwen3"}', "tokenizer.json": "{}", "tokenizer_config.json": "{}", "model.safetensors": "weights"}
            for name, value in files.items():
                (model / name).write_text(value)
            (model / "manifest.json").write_text(json.dumps({"schemaVersion": 1, "model": notes.MODEL_ID, "revision": "a" * 40, "files": {name: len(value) for name, value in files.items()}}))
            with patch.object(notes, "runtime_available", return_value=True):
                self.assertTrue(notes.model_status(model)["ready"])
            (model / "model.safetensors").write_text("bad")
            self.assertFalse(notes.model_status(model)["ready"])

    def test_input_validation_and_exact_output_envelope(self):
        source = {"segments": [{"id": "s1", "text": "Привет", "start": 0, "end": 1}], "preset": "meeting"}
        self.assertEqual(notes.validate_input(source), source)
        for bad in ({**source, "preset": "other"}, {**source, "segments": source["segments"] * 2}):
            with self.assertRaises(notes.NotesError):
                notes.validate_input(bad)
        output = notes.output_envelope(sections(), "a" * 40)
        self.assertEqual(set(output), {"schemaVersion", "model", "revision", "promptVersion", "sections"})

    def test_analysis_pipeline_covers_each_chunk_and_writes_atomically(self):
        source = {"segments": [{"id": "s1", "text": "Обсуждение. " * 1300, "start": 0, "end": 2}], "preset": "mentoring"}
        calls = []
        def generate(prompt):
            calls.append(prompt)
            return json.dumps({"sections": sections()}), "stop"
        result = notes.analyze_payload(source, CharacterTokenizer(), generate, "b" * 40, context_tokens=6000, output_tokens=800)
        self.assertGreater(len(calls), 1)
        self.assertEqual(result["sections"], sections())
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "notes.json"
            notes.atomic_write_json(output, result)
            self.assertEqual(json.loads(output.read_text()), result)
            self.assertEqual(list(Path(directory).iterdir()), [output])

    def test_null_timestamp_pair_is_allowed_but_mixed_or_invalid_pairs_fail(self):
        segment = {"id": "s1", "text": "Текст", "start": None, "end": None}
        self.assertEqual(notes.validate_input({"preset": "meeting", "segments": [segment]})["segments"], [segment])
        for start, end in ((None, 1), (0, None), (-1, 1), (2, 1), (float("nan"), 1), (True, 1)):
            with self.subTest(start=start, end=end), self.assertRaises(notes.NotesError):
                notes.validate_input({"preset": "meeting", "segments": [{**segment, "start": start, "end": end}]})

    def test_missing_runtime_is_not_ready_even_when_model_exists(self):
        with patch.object(notes, "require_model", return_value={}), patch.object(notes.importlib.util, "find_spec", return_value=None):
            self.assertEqual(notes.model_status("unused"), {"ready": False, "message": "local_runtime_missing"})

    def test_offline_mode_set_before_incomplete_model_failure(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(notes.NotesError):
                notes.analyze_file(directory, "missing", "missing")
            self.assertEqual(os.environ["HF_HUB_OFFLINE"], "1")
            self.assertEqual(os.environ["TRANSFORMERS_OFFLINE"], "1")

    def test_prepare_uses_resolved_revision_and_never_marks_partial_download_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            files = {"config.json": "{}", "tokenizer.json": "{}", "tokenizer_config.json": "{}", "model.safetensors": "weights"}
            info = SimpleNamespace(sha="c" * 40, siblings=[SimpleNamespace(rfilename=name, size=len(value)) for name, value in files.items()])
            calls = []
            def download(**kwargs):
                calls.append(kwargs)
                for name, value in files.items():
                    (Path(kwargs["local_dir"]) / name).write_text(value)
            module = SimpleNamespace(HfApi=lambda: SimpleNamespace(model_info=lambda *a, **kw: info), snapshot_download=download)
            with patch.dict("sys.modules", {"huggingface_hub": module}):
                notes.prepare_model(directory)
                self.assertEqual(calls[0]["revision"], "c" * 40)
                self.assertEqual(notes.require_model(directory)["revision"], "c" * 40)
                (Path(directory) / "model.safetensors").unlink()
                original_manifest = (Path(directory) / "manifest.json").read_bytes()
                module.snapshot_download = lambda **kwargs: None
                with self.assertRaises(notes.NotesError):
                    notes.prepare_model(directory)
                self.assertEqual((Path(directory) / "manifest.json").read_bytes(), original_manifest)

    def test_prepare_repairs_dirty_directory_repeatedly_using_clean_staging(self):
        with tempfile.TemporaryDirectory() as parent:
            directory = Path(parent) / "notes-model"
            directory.mkdir()
            files = {"config.json": "{}", "tokenizer.json": "{}", "tokenizer_config.json": "{}", "model.safetensors": "weights"}
            info = SimpleNamespace(sha="c" * 40, siblings=[SimpleNamespace(rfilename=name, size=len(value)) for name, value in files.items()])
            downloads = []
            def download(**kwargs):
                target = Path(kwargs["local_dir"])
                self.assertNotEqual(target, directory)
                self.assertEqual(list(target.iterdir()), [])
                downloads.append(target)
                for name, value in files.items():
                    (target / name).write_text(value)
            module = SimpleNamespace(HfApi=lambda: SimpleNamespace(model_info=lambda *a, **kw: info), snapshot_download=download)
            with patch.dict("sys.modules", {"huggingface_hub": module}):
                for artifact in ("old.safetensors", ".cache/huggingface/download/residual.incomplete"):
                    extra = directory / artifact
                    extra.parent.mkdir(parents=True, exist_ok=True)
                    extra.write_text("old incomplete data")
                    notes.prepare_model(directory)
                    self.assertEqual(notes.require_model(directory)["revision"], "c" * 40)
                    self.assertFalse(extra.exists())
                    self.assertEqual(list(Path(parent).iterdir()), [directory])
            self.assertEqual(len(downloads), 2)

    def test_failed_download_or_validation_preserves_existing_model_and_cleans_staging(self):
        for failure in ("download", "validation"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as parent:
                directory = Path(parent) / "notes-model"
                directory.mkdir()
                files = {"config.json": "{}", "tokenizer.json": "{}", "tokenizer_config.json": "{}", "model.safetensors": "weights"}
                for name, value in files.items():
                    (directory / name).write_text(value)
                manifest = {"schemaVersion": 1, "model": notes.MODEL_ID, "revision": "a" * 40, "files": {name: len(value) for name, value in files.items()}}
                (directory / "manifest.json").write_text(json.dumps(manifest))
                before = {p.name: p.read_bytes() for p in directory.iterdir()}
                info = SimpleNamespace(sha="c" * 40, siblings=[SimpleNamespace(rfilename=name, size=len(value)) for name, value in files.items()])
                def download(**kwargs):
                    target = Path(kwargs["local_dir"])
                    for name, value in files.items():
                        (target / name).write_text(value)
                    if failure == "download":
                        raise OSError("network failure")
                    (target / "old.safetensors").write_text("extra weights")
                module = SimpleNamespace(HfApi=lambda: SimpleNamespace(model_info=lambda *a, **kw: info), snapshot_download=download)
                # Simulate an initial stale availability result; the old snapshot
                # itself is valid and must survive any attempted replacement.
                real_require = notes.require_model
                scanned = False
                def require(path):
                    nonlocal scanned
                    if not scanned:
                        scanned = True
                        raise notes.NotesError("incomplete_model")
                    return real_require(path)
                with patch.dict("sys.modules", {"huggingface_hub": module}), patch.object(notes, "require_model", side_effect=require):
                    with self.assertRaises((notes.NotesError, OSError)):
                        notes.prepare_model(directory)
                self.assertEqual({p.name: p.read_bytes() for p in directory.iterdir()}, before)
                self.assertEqual(real_require(directory), manifest)
                self.assertEqual(list(Path(parent).iterdir()), [directory])

    def test_publish_failure_restores_old_directory(self):
        with tempfile.TemporaryDirectory() as parent:
            directory = Path(parent) / "notes-model"
            directory.mkdir()
            (directory / "keep.txt").write_text("old data")
            files = {"config.json": "{}", "tokenizer.json": "{}", "tokenizer_config.json": "{}", "model.safetensors": "weights"}
            info = SimpleNamespace(sha="c" * 40, siblings=[SimpleNamespace(rfilename=name, size=len(value)) for name, value in files.items()])
            def download(**kwargs):
                for name, value in files.items():
                    (Path(kwargs["local_dir"]) / name).write_text(value)
            module = SimpleNamespace(HfApi=lambda: SimpleNamespace(model_info=lambda *a, **kw: info), snapshot_download=download)
            replace = os.replace
            def fail_publish(source, target):
                if Path(source).name == "model" and Path(target) == directory.resolve():
                    raise OSError("cannot publish")
                return replace(source, target)
            with patch.dict("sys.modules", {"huggingface_hub": module}), patch.object(notes.os, "replace", side_effect=fail_publish):
                with self.assertRaises(OSError):
                    notes.prepare_model(directory)
            self.assertEqual((directory / "keep.txt").read_text(), "old data")
            self.assertEqual(list(directory.iterdir()), [directory / "keep.txt"])
            self.assertEqual(list(Path(parent).iterdir()), [directory])

    def _start_slow_prepare(self, parent):
        directory = Path(parent) / "notes-model"
        directory.mkdir()
        (directory / "keep.txt").write_text("old model data")
        ready = Path(parent) / "download-started"
        program = """import importlib.util, sys, time
from pathlib import Path
from types import SimpleNamespace
spec=importlib.util.spec_from_file_location('worker', HELPER_PATH)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
info=SimpleNamespace(sha='c'*40,siblings=[SimpleNamespace(rfilename='model.safetensors',size=10)])
def download(**kwargs):
    stage=Path(kwargs['local_dir'])
    (stage/'partial.incomplete').write_bytes(b'x' * 1024 * 1024)
    Path(READY_PATH).write_text(str(stage))
    time.sleep(60)
sys.modules['huggingface_hub']=SimpleNamespace(HfApi=lambda:SimpleNamespace(model_info=lambda *a,**kw:info),snapshot_download=download)
raise SystemExit(m.main(['prepare','--model-dir',MODEL_PATH]))
""".replace("HELPER_PATH", repr(str(HELPER))).replace("READY_PATH", repr(str(ready))).replace("MODEL_PATH", repr(str(directory)))
        child = subprocess.Popen([sys.executable, "-c", program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        deadline = time.monotonic() + 10
        while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        if not ready.exists():
            child.kill()
            stdout, stderr = child.communicate(timeout=5)
            self.fail(f"Slow preparation did not start: {stdout!r} {stderr!r}")
        return child, directory, Path(ready.read_text())

    def test_sigterm_cleans_owned_preparation_and_preserves_old_model(self):
        with tempfile.TemporaryDirectory() as parent:
            child, directory, stage = self._start_slow_prepare(parent)
            try:
                child.terminate()
                stdout, stderr = child.communicate(timeout=5)
                self.assertEqual(child.returncode, 1)
                self.assertEqual(json.loads(stdout)["message"], "preparation_cancelled")
                self.assertFalse(stage.exists())
                self.assertFalse(list(Path(parent).glob(".notes-model-prepare-*")))
                self.assertEqual((directory / "keep.txt").read_text(), "old model data")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate(timeout=5)

    def test_stale_preparation_recovery_preserves_live_and_unowned_directories(self):
        with tempfile.TemporaryDirectory() as parent:
            child, directory, stage = self._start_slow_prepare(parent)
            try:
                notes.clean_abandoned_preparations(directory.resolve())
                self.assertTrue(stage.exists(), "A live worker still owns this staging directory")
                child.kill()
                child.communicate(timeout=5)
                self.assertTrue(stage.exists())
                unrelated = Path(parent) / ".notes-model-prepare-unowned"
                unrelated.mkdir()
                (unrelated / "keep.txt").write_text("unowned data")
                notes.clean_abandoned_preparations(directory.resolve())
                self.assertFalse(stage.exists())
                self.assertTrue(unrelated.exists())
                self.assertEqual((directory / "keep.txt").read_text(), "old model data")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate(timeout=5)

    def test_full_candidate_name_is_rejected_in_interview_output(self):
        source = {"preset": "interview", "segments": [{"id": "s1", "text": "Ответ кандидата", "start": 0, "end": 1}]}
        def generate(prompt):
            return json.dumps({"sections": sections(text="Иванов Иван Иванович ответил верно.")}), "stop"
        with self.assertRaises(notes.NotesError):
            notes.analyze_payload(source, CharacterTokenizer(), generate, "d" * 40)

    def test_oversized_output_and_unfinished_inference_never_replace_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "notes.json"
            output.write_text("existing")
            with patch.object(notes, "MAX_OUTPUT_BYTES", 4), self.assertRaises(notes.NotesError):
                notes.atomic_write_json(output, {"private": "content"})
            self.assertEqual(output.read_text(), "existing")
        source = {"preset": "meeting", "segments": [{"id": "s1", "text": "Текст", "start": 0, "end": 1}]}
        with self.assertRaises(notes.NotesError):
            notes.analyze_payload(source, CharacterTokenizer(), lambda _: ('{"sections":[]}', "length"), "d" * 40)

    def test_cli_error_does_not_echo_library_exception_or_transcript(self):
        output = io.StringIO()
        with patch.object(notes, "analyze_file", side_effect=ValueError("PRIVATE TRANSCRIPT")), contextlib.redirect_stdout(output):
            self.assertEqual(notes.main(["analyze", "--model-dir", "model", "--input", "input", "--output", "out"]), 1)
        self.assertNotIn("PRIVATE", output.getvalue())
        self.assertEqual(json.loads(output.getvalue())["message"], "local_notes_failed")

    def test_chunk_count_and_too_small_context_fail_instead_of_dropping_text(self):
        source = [{"id": "s1", "text": "Очень длинный текст. " * 2000, "start": None, "end": None}]
        with patch.object(notes, "MAX_CHUNKS", 1), self.assertRaises(notes.NotesError):
            notes.pack_segments(source, CharacterTokenizer(), "meeting", 6000, 800)
        with self.assertRaises(notes.NotesError):
            notes.pack_segments(source, CharacterTokenizer(), "meeting", 1000, 800)

    def test_model_with_untracked_extra_weights_is_not_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory)
            files = {"config.json": "{}", "tokenizer.json": "{}", "tokenizer_config.json": "{}", "model.safetensors": "weights"}
            for name, value in files.items():
                (model / name).write_text(value)
            (model / "manifest.json").write_text(json.dumps({"schemaVersion": 1, "model": notes.MODEL_ID, "revision": "a" * 40, "files": {name: len(value) for name, value in files.items()}}))
            (model / "model-old.safetensors").write_text("old weights")
            with self.assertRaises(notes.NotesError):
                notes.require_model(model)

    def test_missing_index_shard_is_not_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory)
            files = {"config.json": "{}", "tokenizer.json": "{}", "tokenizer_config.json": "{}", "model-00001.safetensors": "weights",
                     "model.safetensors.index.json": json.dumps({"weight_map": {"a": "model-00001.safetensors", "b": "model-00002.safetensors"}})}
            for name, value in files.items():
                (model / name).write_text(value)
            (model / "manifest.json").write_text(json.dumps({"schemaVersion": 1, "model": notes.MODEL_ID, "revision": "a" * 40, "files": {name: len(value) for name, value in files.items()}}))
            with self.assertRaises(notes.NotesError):
                notes.require_model(model)


if __name__ == "__main__":
    unittest.main()
