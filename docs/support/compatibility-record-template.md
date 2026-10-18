# Compatibility record template

Use this template for one specific model and execution configuration. Submit it through the [GitHub compatibility report form](https://github.com/bidlar/bidlar.github.io/issues/new?template=compatibility-report.yml), or propose a documentation change in the repository.

For a documentation-only entry, write **not tested** for measurements and test outcomes. Use **not specified by source** when a vendor document does not provide a required detail. Do not invent device specifications or performance numbers.

## Identification and evidence

| Field | Value to supply |
| --- | --- |
| Record title | Exact model/artifact and target configuration. |
| Task | For example, text generation, transcription, or image classification. |
| Evidence source | Official documentation, community test, or maintainer test. |
| Source links | Specific model card, versioned guide, release note, or test report. |
| Source revision/date | Document version or commit and the date it was checked. |
| Test date | Date of actual execution, or not tested. |
| Review state | Awaiting review; maintained separately from the reporter's result. |

## Model and environment

| Field | Value to supply |
| --- | --- |
| Model | Full repository identifier and immutable revision where available. |
| Artifact | Exact optimized artifact, format, file checksum where available. |
| Precision | Weight/activation precision and quantization settings. |
| Preparation | Conversion or compilation tools, versions, and commands; write prebuilt when applicable. |
| Hardware | Processor model and NPU generation/model; include device model if relevant. |
| Memory | Installed RAM, measured peak memory if available, and source for any minimum requirement. |
| Operating system | OS version/build and architecture. |
| Driver | Exact NPU driver version. |
| Runtime | Execution framework, backend/provider, and exact versions. |
| Application | Application version; for web tests include browser version and WebNN settings. |
| Execution settings | Requested device, fallback settings, context limits, and other relevant options. |

## Installation and reproduction

Provide these steps with the actual commands and expected success indicators:

1. Check the prerequisites and whether the runtime can enumerate the target NPU.
2. Create the documented isolated environment.
3. Install pinned dependencies from their official sources.
4. Obtain the specified model revision/artifact, including any required license acceptance.
5. Convert or compile the model if needed, preserving the exact command and settings.
6. Run a fixed, non-sensitive test input and record its result.
7. Capture device-assignment or execution-provider evidence and any fallback behavior.
8. Document cleanup and recovery for the changes made during setup.

## Result and limitations

| Field | Value to supply |
| --- | --- |
| Outcome | Successful, partially successful, failed, or not tested. |
| Actual execution | NPU, hybrid, CPU/GPU only, or unknown, with evidence. |
| Output check | What was checked to judge whether output was usable/correct. |
| Input/settings | Prompt or test input, token limits, context length, generation settings/seed when applicable. |
| Performance | Measured values with units and run count; separate cold start from warm runs. |
| Energy/power | Measurement method and values, or not measured. |
| Constraints | Context limits, unsupported features, runtime errors, and reproducible failure steps. |
| Attachments | Sanitized logs, commands, or screenshots that support the specific claims. |

NPU utilization alone is not proof that all model operations ran on the NPU. If the execution mode cannot be established, report **unknown**. A successful native application test does not establish browser support.

## Maintainer review

Maintainers record the review date, source checks, gaps, and any independent reproduction. Preserve conflicting results rather than replacing them with a single unconditional supported/unsupported label.

Never attach credentials, service-role keys, authentication tokens, private prompts, or unsanitized personal paths. Linking to an upstream model does not change its license or access requirements.
