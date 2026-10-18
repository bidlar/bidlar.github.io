# Model compatibility and reproducible setup roadmap

NPU.top aims to help people find which models have evidence of working on their hardware, follow a documented setup, and contribute results that others can reproduce.

This page describes the proposed direction. A feature listed here is not a claim that it is already available, and a model listed in a future catalog must not be described as tested without supporting evidence.

## Start with useful records

The first milestone is a small, maintained collection of model configurations with reliable sources. The project can begin by documenting official support statements and accepting community tests; owning every supported device is not a prerequisite.

Borrow the model-card and community-contribution approach from Hugging Face. Each model page should link to its original model repository and group the available deployment configurations by hardware and runtime. Model files can remain with their original publishers.

A configuration records:

**Model revision + model artifact/precision + device + operating system + driver + runtime + execution settings.**

One successful test applies to that configuration. It does not establish support across a whole processor family, every quantization, or every software version.

## Proposed browsing flow

1. Choose a processor or NPU platform and operating system.
2. Browse models and the evidence available for each configuration.
3. Open an installation guide for the selected configuration.
4. Run the guide's validation steps.
5. Submit a successful or failed reproduction with its environment and evidence.

Proposed areas:

| Area | Purpose |
| --- | --- |
| Models | Model cards, artifact links, deployment configurations, and limitations. |
| Hardware | Find configurations reported for a specific processor or NPU. |
| Guides | Driver installation, isolated runtime setup, validation, and troubleshooting. |
| Contribute | Submit sources, installation recipes, and reproducibility reports. |

These are proposed catalog features. The initial version can use documentation pages and GitHub Issues before adding interactive filters or accounts for submissions.

## Represent evidence honestly

Keep the following dimensions separate:

| Dimension | Example values |
| --- | --- |
| Evidence source | Official documentation; community test; maintainer test. |
| Execution result | Not tested; successful; partially successful; failed. |
| Execution device | NPU; hybrid CPU/GPU/NPU; CPU/GPU only; unknown. |
| Editorial review | Awaiting review; source checked; independently reproduced. |

Every record needs a source link or test evidence, an observation date, and a last-reviewed date. An official statement can be source-checked without being independently reproduced. No available record means **unknown**, not unsupported.

Runtime logs or device-assignment reports should support claims about NPU execution. A device-utilization screenshot alone does not establish that the entire model ran on the NPU. Record hybrid execution explicitly.

Native runtime support and browser/WebNN support are separate configurations. A model that runs in a desktop program is not automatically supported in a browser. PC and mobile results also require separate target-device records.

## What a reproducible guide contains

- **Prerequisites:** exact tested device, operating system, memory, driver, and available disk space; distinguish official minimum requirements from the tested machine's specifications.
- **Pinned inputs:** runtime and dependency versions, model repository revision, artifact format, quantization, conversion/compilation commands, and relevant settings. Include checksums for fixed artifacts when available.
- **Installation:** official download links, an isolated environment, copyable commands, expected outputs, and any required restart or license step.
- **Validation:** a fixed input/prompt, input and output token limits where relevant, generation settings, correctness checks, and device-assignment evidence.
- **Measurements:** distinguish first compilation, model loading, first-token latency, and steady-state generation speed. Record units, run count, context length, and power mode. Leave unmeasured fields blank or mark them not measured.
- **Recovery:** known errors, environment cleanup, and recovery instructions for changes made by the guide. Driver changes need their own documented recovery path.

A guide remains **awaiting reproduction** until someone has followed it on an eligible device and attached evidence. Independent reproduction strengthens confidence but does not guarantee every matching device will behave identically.

## Contribution workflow

1. Start from the [compatibility record template](support/compatibility-record-template.md).
2. Submit a [compatibility report](https://github.com/bidlar/bidlar.github.io/issues/new?template=compatibility-report.yml).
3. Maintainers check the sources, environment details, and reported execution mode. Request missing information instead of guessing.
4. Publish the record with its evidence and review state, linking back to the report.
5. Preserve prior results when updating versions. Link conflicting and failed tests so limitations remain visible.

Reports are not automatically treated as verified measurements. Remove tokens, passwords, personal prompts, usernames in local paths, and other private information from logs before submitting.

## Initial scope and acceptance criteria

Start with a few well-documented configurations across the platforms for which reliable sources can be found. Document an actual supported artifact rather than filling a quota with unverified model names.

The first release is useful when a reader can:

- Identify whether there is evidence for their configuration.
- Find a versioned setup recipe, or clearly see that no recipe has been validated.
- Understand the execution mode and known limitations.
- Submit enough information for another person to reproduce success or failure.

Track installation completion and independent reproductions before investing in a cross-device score or leaderboard. Any later benchmark comparison must hold workload, quality expectations, precision, context, and methodology sufficiently consistent and disclose remaining differences.

## Starting points for research

These links are discovery sources, not blanket compatibility claims. Check the relevant release and target hardware before creating a record.

- [Hugging Face model cards](https://huggingface.co/docs/hub/model-cards)
- [OpenVINO documentation](https://docs.openvino.ai/)
- [AMD Ryzen AI documentation](https://ryzenai.docs.amd.com/)
- [Qualcomm AI Hub models](https://aihub.qualcomm.com/models)
- [Qualcomm AI Hub Models repository](https://github.com/qualcomm/ai-hub-models)
