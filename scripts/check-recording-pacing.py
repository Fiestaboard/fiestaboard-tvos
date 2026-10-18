#!/usr/bin/env python3
"""Reject source recordings with missing samples during known moving intervals.

Run on the original variable-rate capture, before fps conversion duplicates
frames and hides missing timestamps. A pass checks capture cadence only; it
cannot establish that the app drew a distinct animation frame at each sample.
"""
import argparse
import json
import subprocess


def measure(times, intervals, maximum_gap):
    gaps = []
    for start, end in intervals:
        selected = [t for t in times if start <= t <= end]
        if len(selected) < 2:
            raise ValueError(f'Insufficient samples in moving interval {start}:{end}')
        gaps.extend((a, b, b - a) for a, b in zip(selected, selected[1:]))
    failures = [(a, b, gap) for a, b, gap in gaps if gap > maximum_gap + 1e-6]
    return {'sample_intervals': len(gaps), 'maximum_gap_ms': max(g[2] for g in gaps) * 1000,
            'gaps_over_limit': len(failures),
            'missing_samples': [{'from': a, 'to': b, 'gap_ms': gap * 1000} for a, b, gap in failures],
            'passed': not failures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('movie')
    parser.add_argument('--motion', action='append', required=True, metavar='START:END')
    parser.add_argument('--max-gap-ms', type=float, default=50)
    args = parser.parse_args()
    intervals = [tuple(map(float, span.split(':'))) for span in args.motion]
    if any(len(span) != 2 or span[0] < 0 or span[0] >= span[1] for span in intervals):
        parser.error('Motion intervals must be positive START:END ranges')
    data = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_frames',
        '-show_entries', 'frame=pts_time', '-of', 'json', args.movie]))
    # Xcode's decode timestamps can mislead FFmpeg's best-effort heuristic.
    # Measure original presentation timestamps, as used for visible playback.
    times = [float(frame['pts_time']) for frame in data['frames']]
    result = measure(times, intervals, args.max_gap_ms / 1000)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
