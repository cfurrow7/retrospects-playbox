// Engine_RetroBox: 8-voice sample drum machine for Retrospects Playbox
// (Renamed from DrumBox to avoid duplicate engine conflict with midi-playbox)

Engine_RetroBox : CroneEngine {
    var <buffers;
    var <masterAmp;
    var <drumBus;
    var <filterSynth;
    var <delaySynth;
    var <lpfFreq;
    var <lpfRes;
    var <delayTime;
    var <delayFeedback;
    var <delayMix;

    alloc {
        masterAmp = 0.8;
        lpfFreq = 20000;
        lpfRes = 0.3;
        delayTime = 0.3;
        delayFeedback = 0.0;
        delayMix = 0.0;

        buffers = Array.fill(8, { nil });
        drumBus = Bus.audio(context.server, 2);

        SynthDef(\retrobox_sample, { |out=0, buf=0, amp=0.5, rate=1, pan=0|
            var sig = PlayBuf.ar(1, buf, rate * BufRateScale.kr(buf), doneAction: 2);
            Out.ar(out, Pan2.ar(sig * amp, pan));
        }).add;

        SynthDef(\retrobox_sample_stereo, { |out=0, buf=0, amp=0.5, rate=1|
            var sig = PlayBuf.ar(2, buf, rate * BufRateScale.kr(buf), doneAction: 2);
            Out.ar(out, sig * amp);
        }).add;

        SynthDef(\retrobox_filter, { |in, out=0, lpf=20000, res=0.3|
            var sig = In.ar(in, 2);
            sig = RLPF.ar(sig, lpf.clip(20, 20000), res.clip(0.05, 1.0));
            Out.ar(out, sig);
        }).add;

        SynthDef(\retrobox_delay, { |in, out=0, time=0.3, feedback=0.3, mix=0.0|
            var dry = In.ar(in, 2);
            var left = CombL.ar(dry[0], 2.0, time, feedback * 6);
            var right = CombL.ar(dry[1], 2.0, time * 1.05, feedback * 6);
            var wet = [left, right];
            Out.ar(out, dry + (wet * mix));
        }).add;

        SynthDef(\retrobox_kick, { |out=0, amp=0.5, pan=0|
            var pitchEnv = EnvGen.kr(Env.perc(0.001, 0.07));
            var body = SinOsc.ar(42 + (42 * 5 * pitchEnv));
            var click = WhiteNoise.ar * EnvGen.kr(Env.perc(0.001, 0.01)) * 0.3;
            var env = EnvGen.kr(Env.perc(0.001, 0.9, curve: -6), doneAction: 2);
            Out.ar(out, Pan2.ar((body + click) * env * amp, pan));
        }).add;

        SynthDef(\retrobox_snare, { |out=0, amp=0.5, pan=0|
            var tone = SinOsc.ar(180) * EnvGen.kr(Env.perc(0.001, 0.1, curve: -8)) * 0.4;
            var noise = BPF.ar(WhiteNoise.ar, 720, 2) * EnvGen.kr(Env.perc(0.005, 0.2, curve: -4), doneAction: 2) * 0.7;
            Out.ar(out, Pan2.ar((tone + noise) * amp, pan));
        }).add;

        SynthDef(\retrobox_chh, { |out=0, amp=0.5, pan=0|
            var env = EnvGen.kr(Env.perc(0.001, 0.04, curve: -8), doneAction: 2);
            Out.ar(out, Pan2.ar(BPF.ar(WhiteNoise.ar, 8000, 0.3) * env * amp * 2, pan));
        }).add;

        SynthDef(\retrobox_ohh, { |out=0, amp=0.5, pan=0|
            var env = EnvGen.kr(Env.perc(0.001, 0.3, curve: -4), doneAction: 2);
            Out.ar(out, Pan2.ar(BPF.ar(WhiteNoise.ar, 8000, 0.3) * env * amp * 2, pan));
        }).add;

        SynthDef(\retrobox_clap, { |out=0, amp=0.5, pan=0|
            var e1 = EnvGen.kr(Env.perc(0.001, 0.01));
            var e2 = EnvGen.kr(Env.perc(0.001, 0.01), delay: 0.01);
            var e3 = EnvGen.kr(Env.perc(0.001, 0.15), delay: 0.02, doneAction: 2);
            Out.ar(out, Pan2.ar(BPF.ar(WhiteNoise.ar, 1200, 0.5) * (e1 + e2 + e3) * amp * 0.5, pan));
        }).add;

        SynthDef(\retrobox_tom, { |out=0, freq=100, amp=0.5, pan=0|
            var pitchEnv = EnvGen.kr(Env.perc(0.001, 0.05));
            var body = SinOsc.ar(freq + (freq * 2 * pitchEnv));
            var env = EnvGen.kr(Env.perc(0.001, 0.3, curve: -6), doneAction: 2);
            Out.ar(out, Pan2.ar(body * env * amp, pan));
        }).add;

        SynthDef(\retrobox_cymbal, { |out=0, amp=0.5, pan=0|
            var env = EnvGen.kr(Env.perc(0.001, 1.5, curve: -3), doneAction: 2);
            var noise = BPF.ar(WhiteNoise.ar, 6000, 0.1);
            var ring = SinOsc.ar(6000 * 1.37) * 0.1 + (SinOsc.ar(6000 * 2.42) * 0.05);
            Out.ar(out, Pan2.ar((noise + ring) * env * amp, pan));
        }).add;

        context.server.sync;

        filterSynth = Synth(\retrobox_filter, [
            \in, drumBus, \out, 0,
            \lpf, lpfFreq, \res, lpfRes
        ], addAction: \addToTail);

        delaySynth = Synth(\retrobox_delay, [
            \in, drumBus, \out, 0,
            \time, delayTime, \feedback, delayFeedback, \mix, delayMix
        ], addAction: \addToTail);

        this.addCommand(\load_sample, "is", { |msg|
            var voice = msg[1].asInteger.clip(0, 7);
            var path = msg[2].asString;
            if (buffers[voice].notNil, { buffers[voice].free });
            Buffer.read(context.server, path, action: { |buf|
                buffers[voice] = buf;
            });
        });

        this.addCommand(\trig_kit, "if", { |msg|
            var voice = msg[1].asInteger.clip(0, 7);
            var vel = msg[2].asFloat.clip(0, 1);
            var amp = vel * masterAmp;
            var pans = [0, 0, 0.15, 0.15, 0, -0.3, 0.3, 0.2];

            if (buffers[voice].notNil, {
                Synth(\retrobox_sample, [
                    \out, drumBus, \buf, buffers[voice],
                    \amp, amp, \rate, 1, \pan, pans[voice]
                ], addAction: \addToHead);
            }, {
                var synthNames = [
                    \retrobox_kick, \retrobox_snare, \retrobox_chh, \retrobox_ohh,
                    \retrobox_clap, \retrobox_tom, \retrobox_tom, \retrobox_cymbal
                ];
                var params = [\out, drumBus, \amp, amp, \pan, pans[voice]];
                if (voice == 5, { params = params ++ [\freq, 80] });
                if (voice == 6, { params = params ++ [\freq, 160] });
                Synth(synthNames[voice], params, addAction: \addToHead);
            });
        });

        this.addCommand(\kit, "i", { |msg| });

        this.addCommand(\amp, "f", { |msg|
            masterAmp = msg[1].asFloat.clip(0, 1);
        });

        this.addCommand(\lpf, "f", { |msg|
            lpfFreq = msg[1].asFloat.clip(20, 20000);
            if (filterSynth.notNil, { filterSynth.set(\lpf, lpfFreq) });
        });

        this.addCommand(\res, "f", { |msg|
            lpfRes = msg[1].asFloat.clip(0.05, 1.0);
            if (filterSynth.notNil, { filterSynth.set(\res, lpfRes) });
        });

        this.addCommand(\delay_time, "f", { |msg|
            delayTime = msg[1].asFloat.clip(0.01, 2.0);
            if (delaySynth.notNil, { delaySynth.set(\time, delayTime) });
        });

        this.addCommand(\delay_feedback, "f", { |msg|
            delayFeedback = msg[1].asFloat.clip(0, 0.95);
            if (delaySynth.notNil, { delaySynth.set(\feedback, delayFeedback) });
        });

        this.addCommand(\delay_mix, "f", { |msg|
            delayMix = msg[1].asFloat.clip(0, 1);
            if (delaySynth.notNil, { delaySynth.set(\mix, delayMix) });
        });

        this.addCommand(\pitch, "f", { |msg| });

        // Randomize and random_keep (same interface as DrumBox)
        this.addCommand(\randomize, "", { |msg| });
        this.addCommand(\random_amt, "f", { |msg| });
        this.addCommand(\random_keep, "", { |msg| });
    }

    free {
        buffers.do { |buf| if (buf.notNil, { buf.free }) };
        if (delaySynth.notNil, { delaySynth.free });
        if (filterSynth.notNil, { filterSynth.free });
        if (drumBus.notNil, { drumBus.free });
    }
}
