import { Router } from 'express';
import { pool } from '../db/client.js';
import { config } from '../config.js';
import { requireUser } from '../lib/auth.js';
import { wrap } from '../lib/wrap.js';
import { validate } from '../lib/validate.js';
import { photoUploadSchema, idParam } from '../lib/schemas.js';

export const photosRouter = Router();

// M7 (skuld 8): bildbearbetningen ligger inte längre i request-tråden. Omskalningen till fyra
// storlekar och signaturerna görs av funktionen process-image (functions/) – lokalt i func start,
// i molnet i Azure Functions. API:et sparar raden, lämnar över jobbet och väntar på svaret.
// M8 (skuld 9): bara inloggade får ladda upp, och bara på sin egen tur. Måtten valideras innan
// något sparas eller skickas till funktionen (photoUploadSchema: heltal, högst 20 000 px).
photosRouter.post(
  '/',
  requireUser,
  validate(photoUploadSchema),
  wrap(async (req, res) => {
    const started = Date.now();
    const { tourId, filename, width, height } = req.body;

    const tour = await pool.query('select user_id from tours where id = $1', [tourId]);
    if (!tour.rows[0]) return res.status(404).json({ error: 'turen finns inte' });
    if (tour.rows[0].user_id !== req.user.id && req.user.role !== 'editor') {
      return res.status(403).json({ error: 'inte din tur' });
    }

    const result = await pool.query(
      'insert into photos (tour_id, filename, width, height) values ($1,$2,$3,$4) returning *',
      [tourId, filename, width, height],
    );

    let processed;
    try {
      const response = await fetch(config.imageFunctionUrl, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          // Funktionsnyckeln (authLevel: 'function'). Tom lokalt – func start kräver ingen nyckel.
          ...(config.imageFunctionKey && { 'x-functions-key': config.imageFunctionKey }),
        },
        body: JSON.stringify({ filename, width, height }),
        signal: AbortSignal.timeout(30_000), // en kallstart i molnet tar sekunder, inte en halv minut
      });
      if (!response.ok) throw new Error(`funktionen svarade ${response.status}`);
      processed = await response.json();
    } catch (err) {
      // err.cause säger varför fetch misslyckades: ECONNREFUSED = ingen lyssnar (func start körs inte?).
      console.error(`Bildtjänsten (${config.imageFunctionUrl}): ${err.message}${err.cause ? ` – ${err.cause.code ?? err.cause.message}` : ''}`);
      return res.status(502).json({ error: 'bildtjänsten svarar inte' });
    }

    res.json({
      ...result.rows[0],
      variants: processed.variants,
      processingMs: processed.processingMs, // funktionens tid för själva bildarbetet
      coldStart: processed.coldStart,
      instance: processed.instance,
      apiMs: Date.now() - started, // API:ets tid för hela anropet: databasen + funktionen + nätet
    });
  }),
);

photosRouter.get(
  '/tour/:tourId',
  wrap(async (req, res) => {
    const id = idParam.safeParse(req.params.tourId);
    if (!id.success) return res.status(400).json({ error: 'ogiltigt id' });
    const result = await pool.query('select * from photos where tour_id = $1', [id.data]);
    res.json(result.rows);
  }),
);
