import React, { Fragment } from 'react'
import { Link } from 'react-router-dom'
import ShareIcon from '../Icons/share'
import HujahCardParent from './card_parent'
import {
  EmailShareButton,
  EmailIcon,
  FacebookShareButton,
  FacebookIcon,
  RedditShareButton,
  RedditIcon,
  TelegramShareButton,
  TelegramIcon,
  TwitterShareButton,
  TwitterIcon,
  WhatsappShareButton,
  WhatsappIcon
} from "react-share"

class HujahCardHeader extends React.Component {
  render() {
    const { hujah, hujahParentAvailable } = this.props
    const { parent, user, body } = hujah.attributes
    const { full_name, username, photo } = user.attributes

    const messageForSocialMedia = `"${body} (by @${username})" Do you AGREE? NEUTRAL? DISAGREE?`
    
    const socialMediaButtonUrl = `${window.location.origin}/hoojah/${hujah.attributes.slug}`
    const socialMediaButtonClass = "px-3 py-1"

    return(
      <Fragment>
        { hujahParentAvailable ? <HujahCardParent hujah={parent} /> : null }

        <div className="card-header border-bottom-0 pb-0 d-flex justify-content-between align-items-center">
          <div className="media">
            <Link to={`/${username}`}><img src={photo} className="rounded-circle mr-3 avatar" /></Link>
            <div className="media-body">
              <div className="d-flex flex-column">
                <Link to={`/${username}`} className="mt-0 mb-0 text-primary">{full_name}</Link>
                <a className="no-underscore handle">
                  <small className="text-muted">{`@${username}`}</small>
                </a>
              </div>
            </div>
          </div>
          <div className="dropdown">
            <button className="btn btn-icon-16 fill-light-grey p-0" type="button" id="moreAction" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
              <ShareIcon />
            </button>
            <div className="dropdown-menu dropdown-menu-right" aria-labelledby="moreAction">
              <h6 className="dropdown-header">Share this hoojah via</h6>
              <FacebookShareButton 
                url={socialMediaButtonUrl}
                quote={messageForSocialMedia} 
                hashtag="#hoojah" 
                className={socialMediaButtonClass}>
                <FacebookIcon size={24} borderRadius={48} className="mr-1" /> Facebook
              </FacebookShareButton>
              <TwitterShareButton 
                url={socialMediaButtonUrl}
                title={messageForSocialMedia}
                via="hoojah_my" 
                hashtags={["hoojah", "discussions", "malaysia"]} 
                className={socialMediaButtonClass}>
                <TwitterIcon size={24} borderRadius={48} className="mr-1" /> Twitter
              </TwitterShareButton>
              <WhatsappShareButton 
                url={socialMediaButtonUrl}
                title={messageForSocialMedia}
                className={socialMediaButtonClass}>
                <WhatsappIcon size={24} borderRadius={48} className="mr-1" /> WhatsApp
              </WhatsappShareButton>
              <TelegramShareButton 
                url={socialMediaButtonUrl}
                title={messageForSocialMedia}
                className={socialMediaButtonClass}>
                <TelegramIcon size={24} borderRadius={48} className="mr-1" /> Telegram
              </TelegramShareButton>
              <RedditShareButton 
                url={socialMediaButtonUrl}
                title={messageForSocialMedia}
                className={socialMediaButtonClass}>
                <RedditIcon size={24} borderRadius={48} className="mr-1" /> Reddit
              </RedditShareButton>
              <EmailShareButton 
                url={socialMediaButtonUrl}
                subject={messageForSocialMedia}
                body="hello@hoojah.my" 
                className={socialMediaButtonClass}>
                <EmailIcon size={24} borderRadius={48} className="mr-1" /> Email
              </EmailShareButton>
            </div>
          </div>
        </div>
      </Fragment>
    )
  }
}

export default HujahCardHeader
