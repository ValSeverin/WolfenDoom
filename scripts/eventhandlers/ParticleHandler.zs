/*
 * Copyright (c) 2020 AFADoomer
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
**/

class ParticleManager : EventHandler
{
	Array<Actor> particlequeue;
	Array<Actor> bloodqueue;
	Array<Actor> debrisqueue;
	Array<Actor> flatdecalqueue;
	transient CVar maxparticlescvar;
	transient CVar maxbloodcvar;
	transient CVar maxdebriscvar;
	transient CVar maxflatdecalscvar;
	int maxparticles, maxblood, maxdebris, maxflatdecals;
	int tickdelay;
	double particlescaling;
	EffectsManager effectmanager;
	
	override void OnRegister()
	{
		maxparticlescvar = CVar.FindCVar("boa_maxparticleactors");
		maxbloodcvar = CVar.FindCVar("sv_corpsequeuesize");
		maxdebriscvar = CVar.FindCVar("boa_maxdebrisactors");
		maxflatdecalscvar = CVar.FindCVar("boa_maxflatdecals");

		maxparticles = 512;
		if (maxparticlescvar) { maxparticles = max(1, maxparticlescvar.GetInt()); }

		maxblood = 1024;
		if (maxbloodcvar) { maxblood = max(1, maxbloodcvar.GetInt()); }

		maxdebris = 64;
		if (maxdebriscvar) { maxdebris = max(1, maxdebriscvar.GetInt()); }

		maxflatdecals = 256;
		if (maxflatdecalscvar) { maxflatdecals = max(1, maxflatdecalscvar.GetInt()); }
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		if (
			e.thing is "Blood" ||			// NashGore actors (and engine default blood)
			e.thing is "BloodSplatter" ||
			e.thing is "NashGore_BloodBase" ||
			e.thing is "BloodPool2" || 		// Droplets actors
			e.thing is "GibletA" || 
			e.thing is "BloodDrop1" ||
			e.thing is "CeilDripper" ||
			e.thing is "BloodFog" ||
			e.thing is "UWBloodFog"
		)
		{
			if (maxbloodcvar) { maxblood = max(0, maxbloodcvar.GetInt()); }
			if (!maxblood) { e.thing.Destroy(); return; }

			bloodqueue.Insert(0, e.thing);
			ConsolidateArray(bloodqueue, maxblood);
		}
		else if (
			e.thing is "Casing9mm" ||		// All shell casings
			e.thing is "Debris_Base"		// Explosion/breakage debris
		)
		{
			if (maxdebriscvar) { maxdebris = max(0, maxdebriscvar.GetInt()); }
			if (!maxdebris) { e.thing.Destroy(); return; }

			debrisqueue.Insert(0, e.thing);
			ConsolidateArray(debrisqueue, maxdebris);
		}
		else if (
			e.thing is "ZFlatDecal"			// Flat decals
		)
		{
			if (maxflatdecalscvar) { maxflatdecals = max(0, maxflatdecalscvar.GetInt()); }
			if (!maxflatdecals) { e.thing.Destroy(); return; }

			flatdecalqueue.Insert(0, e.thing);
			ConsolidateArray(flatdecalqueue, maxflatdecals);
		}
		else if (
			e.thing is "SplashParticleBase"	||	// Ground splash particle actors
			e.thing is "ParticleBase" || 		// Handle all other ParticleBase actors last so that the above can inherit from ParticleBase and still get their own queues
			e.thing is "LightningBeam"		// Lightning segments
		)
		{
			if (maxparticlescvar) { maxparticles = max(0, maxparticlescvar.GetInt()); }
			if (!maxparticles) { e.thing.Destroy(); return; }

			particlequeue.Insert(0, e.thing);
			ConsolidateArray(particlequeue, maxparticles);

			int size = particlequeue.Size();
			if (size > maxparticles * 0.75) { tickdelay = clamp(int((size - (maxparticles * 0.75)) / (maxparticles * 0.25) * 10), 0, 10); }
			else { tickdelay = 0; }

			particlescaling = max(0.1, 1.0 - (tickdelay / 10));

			// Debug output: particle queue size and current tick delay
			if (boa_debugparticles && level.time % 35 == 0) { console.printf("%i of %i particles, %i tick delay", size, maxparticles, tickdelay); }
		}
		else if (e.thing is "BulletTracer")
		{
			if (!effectmanager) { effectmanager = EffectsManager.GetManager(); }
			BulletTracer(e.thing).manager = effectmanager;
		}

		if (boa_noprojectilegravity && (e.Thing is "BulletTracer" || (e.Thing is "GrenadeBase" && e.Thing.DamageType == "Rocket")))
		{
			e.Thing.bNoGravity = true;
		}
	}

	static ParticleManager GetManager()
	{
		return ParticleManager(EventHandler.Find("ParticleManager"));
	}

	void ConsolidateArray(in out Array<Actor> input, int limit)
	{
		Array<Actor> t;
		int count = 0;

		for (int s = 0; s < input.Size(); s++)
		{
			if (!input[s]) { continue; }

			if (count >= limit)
			{
				state FadeState = input[s].FindState("Fade");

				if (FadeState) { input[s].SetState(FadeState); }
				else { input[s].Destroy(); }
			}
			else { t.Push(input[s]); }

			count++;
		}

		input.Move(t);
	}

	int GetDelay(int chunkx, int chunky, Actor origin = null)
	{
		if (!boa_culling) { return 0; }

		if (!effectmanager) { effectmanager = EffectsManager.GetManager(); }

		if (origin)
		{
			[chunkx, chunky] = EffectChunk.GetChunk(origin.pos.x, origin.pos.y);
		}

		if (effectmanager && effectmanager.handler)
		{
			EffectChunk chunk = EffectChunk.FindChunk(chunkx, chunky, effectmanager.handler.chunks);
			if (chunk.range < 2) { return 0; }
			else if (chunk.range > maxinterval) { return 0; }

			int maxinterval = clamp(boa_cullrange, 1024, 8192) / CHUNKSIZE;
			double delayfactor = chunk.range / maxinterval;
			delayfactor = delayfactor ** 2 * chunk.range;

			return int(tickdelay * delayfactor);
		}

		return tickdelay;
	}
}