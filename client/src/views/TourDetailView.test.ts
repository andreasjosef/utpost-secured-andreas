import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/vue'
import type { Photo, TourDetail } from '@utpost/shared'
import TourDetailView from './TourDetailView.vue'
import { get } from '../api'

vi.mock('../api', () => ({ get: vi.fn() }))
vi.mock('vue-router', () => ({ useRoute: () => ({ params: { id: '1' } }) }))
const mockedGet = vi.mocked(get)

const tour: TourDetail = {
  id: 1,
  user_id: 1,
  guide_id: null,
  title: 'Morgontur',
  started_at: '2026-09-01T06:00:00.000Z',
  distance_m: 12345,
  notes: null,
  logs: [],
  photos: [],
}
const photo: Photo = {
  id: 7,
  tour_id: 1,
  filename: 'fjall.jpg',
  width: 4000,
  height: 3000,
  created_at: '2026-11-04T12:00:00.000Z',
}

describe('TourDetailView', () => {
  beforeEach(() => {
    mockedGet.mockImplementation(async (path: string) =>
      path.startsWith('/photos/tour/') ? [photo] : tour,
    )
  })

  it('visar turen, bilderna och länken till den skyddade uppladdningen (M8)', async () => {
    render(TourDetailView, { global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } } })
    await screen.findByText('Morgontur')
    expect(screen.getByText('Turens bilder (1)')).toBeInTheDocument()
    expect(screen.getByText('fjall.jpg · 4000×3000')).toBeInTheDocument()
    expect(screen.getByText('Ladda upp en bild')).toBeInTheDocument()
  })
})
