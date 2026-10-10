import http.client
import io
import json
import tempfile
import threading
import time
import unittest
from email.message import Message
from unittest.mock import patch
from pathlib import Path

import bridge


class BridgeProtocolTests(unittest.TestCase):
    def test_accepts_supported_image_signatures(self) -> None:
        self.assertEqual(
            bridge._validate_image(b"\x89PNG\r\n\x1a\nbytes", "image/png"),
            "image/png",
        )
        self.assertEqual(
            bridge._validate_image(b"\xff\xd8\xffbytes", "image/jpeg"),
            "image/jpeg",
        )
        self.assertEqual(
            bridge._validate_image(b"RIFF0000WEBPbytes", "image/webp"),
            "image/webp",
        )

    def test_rejects_invalid_image_and_request_id(self) -> None:
        with self.assertRaises(bridge.BridgeError):
            bridge._validate_image(b"not an image", "image/png")
        with self.assertRaises(bridge.BridgeError):
            bridge._valid_request_id("../escape")
        with self.assertRaises(bridge.BridgeError):
            bridge._valid_request_id("")
        with self.assertRaises(bridge.BridgeError):
            bridge._valid_relative_component(r"nested\..\escape", "output filename")
        with self.assertRaises(bridge.BridgeError):
            bridge._valid_loopback_url("http://localhost:not-a-port", 8188)
        with self.assertRaises(bridge.BridgeError):
            bridge._valid_loopback_url("http://localhost:0", 8188)
        self.assertEqual(
            bridge._valid_loopback_url("http://localhost:8188", 8188),
            "http://127.0.0.1:8188",
        )
        self.assertEqual(
            bridge._valid_loopback_url("http://[::1]:8188", 8188),
            "http://[::1]:8188",
        )
        self.assertTrue(bridge._origin_allowed("http://localhost:3000", set()))
        self.assertFalse(bridge._origin_allowed("http://user@localhost:3000", set()))

    def test_patches_only_supported_workflow_inputs(self) -> None:
        graph = {
            "1": {"class_type": "LoadImage", "inputs": {"image": "input.png"}},
            "2": {"class_type": "CLIPTextEncode", "inputs": {"text": "positive"}},
            "3": {"class_type": "CLIPTextEncode", "inputs": {"text": "negative"}},
            "4": {
                "class_type": "LTXVImgToVideo",
                "inputs": {
                    "positive": ["2", 0],
                    "negative": ["3", 0],
                    "image": ["1", 0],
                    "width": 768,
                    "height": 512,
                    "length": 97,
                    "batch_size": 1,
                },
            },
            "5": {
                "class_type": "CreateVideo",
                "inputs": {"images": ["8", 0], "fps": 24},
            },
            "6": {
                "class_type": "SaveVideo",
                "inputs": {
                    "filename_prefix": "old",
                    "format": "webm",
                    "codec": "vp9",
                },
            },
            "7": {
                "class_type": "UNETLoader",
                "inputs": {"unet_name": bridge.EXPECTED_CHECKPOINT},
            },
            "8": {
                "class_type": "SamplerCustom",
                "inputs": {"noise_seed": 712395695050634},
            },
            "9": {
                "class_type": "LTXVConditioning",
                "inputs": {"frame_rate": 25},
            },
        }
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "workflow.json"
            path.write_text(json.dumps(graph), encoding="utf-8")
            profile = bridge.WorkflowProfile(path)
            with patch.object(bridge.secrets, "randbelow", return_value=12345):
                patched = profile.patched(
                    "varian_bridge/input.png",
                    "animate the facade",
                    "4",
                    "1280x720",
                    "varian_bridge_test",
                )

        self.assertEqual(patched["1"]["inputs"]["image"], "varian_bridge/input.png")
        self.assertEqual(patched["2"]["inputs"]["text"], "animate the facade")
        self.assertEqual(
            patched["3"]["inputs"]["text"],
            bridge.DEFAULT_NEGATIVE_PROMPT,
        )
        self.assertEqual(patched["4"]["inputs"]["width"], 512)
        self.assertEqual(patched["4"]["inputs"]["height"], 288)
        self.assertEqual(patched["4"]["inputs"]["length"], 33)
        self.assertEqual(patched["5"]["inputs"]["fps"], 8)
        self.assertEqual(patched["9"]["inputs"]["frame_rate"], 8)
        self.assertEqual(patched["6"]["inputs"]["format"], "mp4")
        self.assertEqual(patched["6"]["inputs"]["codec"], "h264")
        self.assertEqual(patched["8"]["inputs"]["noise_seed"], 12345)

    def test_bundled_workflow_patches_low_vram_runtime_inputs(self) -> None:
        profile = bridge.WorkflowProfile(Path(__file__).with_name("workflow_api.json"))
        with patch.object(bridge.secrets, "randbelow", return_value=12345):
            patched = profile.patched(
                "varian_bridge/input.png",
                "animate the facade",
                "4",
                "1280x720",
                "varian_bridge_test",
            )
        self.assertEqual(patched["69"]["inputs"]["frame_rate"], 8)
        self.assertEqual(patched["80"]["inputs"]["fps"], 8)
        self.assertEqual(patched["77"]["inputs"]["length"], 33)
        self.assertEqual(patched["81"]["inputs"]["format"], "mp4")
        self.assertEqual(patched["81"]["inputs"]["codec"], "h264")
        self.assertNotEqual(
            patched["72"]["inputs"]["noise_seed"],
            712395695050634,
        )
        self.assertLess(patched["72"]["inputs"]["noise_seed"], 2**63)

    def test_rejects_workflow_without_mp4_output(self) -> None:
        graph = {
            "1": {"class_type": "LoadImage", "inputs": {"image": "input.png"}},
            "2": {"class_type": "CLIPTextEncode", "inputs": {"text": "positive"}},
            "3": {"class_type": "CLIPTextEncode", "inputs": {"text": "negative"}},
            "4": {"class_type": "LTXVImgToVideo", "inputs": {}},
        }
        with self.assertRaises(bridge.BridgeError):
            bridge.WorkflowProfile._validate_graph(graph)

    def test_low_vram_profile_keeps_aspect_ratio(self) -> None:
        self.assertEqual(bridge._low_vram_dimensions(1280, 720), (512, 288))
        self.assertEqual(bridge._low_vram_dimensions(720, 1280), (288, 512))

    def test_portable_comfy_command_is_standalone_and_does_not_leak_token(self) -> None:
        portable_python = Path(r"C:\ComfyUI_windows_portable\python_embeded\python.exe")
        main = Path(r"C:\ComfyUI_windows_portable\ComfyUI\main.py")
        self.assertIn("--windows-standalone-build", bridge._comfy_command(portable_python, main, 8188))
        regular_python = Path(r"C:\venv\Scripts\python.exe")
        self.assertNotIn("--windows-standalone-build", bridge._comfy_command(regular_python, main, 8188))
        with patch.dict(
            bridge.os.environ,
            {
                "VARIAN_COMFYUI_BRIDGE_TOKEN": "secret-token",
                "CUSTOM_BRIDGE_TOKEN": "custom-secret",
            },
            clear=False,
        ):
            self.assertNotIn("VARIAN_COMFYUI_BRIDGE_TOKEN", bridge._comfy_environment())
            self.assertNotIn(
                "CUSTOM_BRIDGE_TOKEN",
                bridge._comfy_environment("CUSTOM_BRIDGE_TOKEN"),
            )


    def test_lease_starts_after_bridge_is_ready(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state = bridge.BridgeState(
                bridge.ComfyProcess('', 8188, root, True),
                bridge.WorkflowProfile(root / 'workflow.json'),
                'test-token-12345678901234567890',
                set(),
                lease_seconds=1,
            )
            state.last_heartbeat = time.monotonic() - 2
            self.assertFalse(state.lease_expired())
            state.ready = True
            self.assertTrue(state.lease_expired())

    def test_validates_h264_video_track(self) -> None:
        def box(box_type: bytes, payload: bytes) -> bytes:
            return (len(payload) + 8).to_bytes(4, "big") + box_type + payload

        ftyp = box(b"ftyp", b"isom")
        hdlr = box(b"hdlr", b"\0\0\0\0\0\0\0\0vide")
        stsd = box(
            b"stsd",
            b"\0\0\0\0" + (1).to_bytes(4, "big") + box(b"avc1", b""),
        )
        stbl = box(b"stbl", stsd)
        minf = box(b"minf", stbl)
        mdia = box(b"mdia", hdlr + minf)
        moov = box(b"moov", box(b"trak", mdia))
        mdat = box(b"mdat", b"encoded video")
        self.assertTrue(bridge._is_mp4(ftyp + moov + mdat))
        self.assertFalse(bridge._is_mp4(ftyp + moov))
        non_h264 = box(
            b"moov",
            box(
                b"trak",
                box(
                    b"mdia",
                    hdlr
                    + box(
                        b"minf",
                        box(
                            b"stbl",
                            box(
                                b"stsd",
                                b"\0\0\0\0"
                                + (1).to_bytes(4, "big")
                                + box(b"vp09", b""),
                            ),
                        ),
                    ),
                ),
            ),
        )
        self.assertFalse(bridge._is_mp4(ftyp + non_h264 + mdat))

    def test_multipart_parser_and_http_auth_contract(self) -> None:
        content_type, body = bridge._multipart_body(
            {"model": bridge.PROFILE_ID, "prompt": "move"},
            {"input_reference": ("input.png", "image/png", b"\x89PNG\r\n\x1a\nbytes")},
        )

        class Request:
            headers = Message()
            rfile = io.BytesIO(body)

        Request.headers["Content-Length"] = str(len(body))
        Request.headers["Content-Type"] = content_type
        fields, image, image_type = bridge._read_multipart(Request())
        self.assertEqual(fields["model"], bridge.PROFILE_ID)
        self.assertEqual(image_type, "image/png")
        self.assertTrue(image.startswith(b"\x89PNG"))

        with tempfile.TemporaryDirectory() as folder:
            comfy = bridge.ComfyProcess("", 8188, Path(folder), True)
            state = bridge.BridgeState(
                comfy,
                bridge.WorkflowProfile(Path(folder) / "workflow.json"),
                "test-token-12345678901234567890",
                set(),
            )
            state.ready = True
            server = bridge.BridgeHttpServer(("127.0.0.1", 0), state)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                port = server.server_address[1]
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                connection.request("GET", "/v1/videos")
                response = connection.getresponse()
                self.assertEqual(response.status, 401)
                response.read()
                connection.close()

                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                connection.request(
                    "GET",
                    "/v1/videos",
                    headers={"Authorization": "Bearer test-token-12345678901234567890"},
                )
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read())["data"], [])
                connection.close()
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=3)

    def test_rejects_cross_job_output_and_prunes_workspace(self) -> None:
        output = {"1": {"videos": [{"filename": "varian_bridge_other.mp4"}]}}
        self.assertIsNone(bridge._find_output(output, "varian_bridge_current"))
        with self.assertRaises(bridge.BridgeError):
            bridge._find_output(
                {"1": {"videos": [{"filename": "../varian_bridge_current.mp4"}]}},
                "varian_bridge_current",
            )

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            comfy = bridge.ComfyProcess("", 8188, root, True)
            state = bridge.BridgeState(
                comfy,
                bridge.WorkflowProfile(root / "workflow.json"),
                "test-token-12345678901234567890",
                set(),
            )
            old = bridge.Job("old-job", status="completed")
            old.updated_at = time.time() - bridge.JOB_RETENTION_SECONDS - 1
            state.jobs[old.id] = old
            workspace = root / "bridge_jobs" / old.id
            workspace.mkdir(parents=True)
            (workspace / "input.png").write_bytes(b"temporary")
            state._prune_jobs()
            self.assertNotIn(old.id, state.jobs)
            self.assertFalse(workspace.exists())

if __name__ == "__main__":
    unittest.main()
